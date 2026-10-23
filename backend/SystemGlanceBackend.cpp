#include "SystemGlanceBackend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTextStream>
#include <QUrl>
#include <algorithm>
#include <sys/statvfs.h>
#include <unistd.h>

namespace {
QString resolveUserConfigDir()
{
    const QString xdg = qEnvironmentVariable("XDG_CONFIG_HOME").trimmed();
    if (!xdg.isEmpty())
        return xdg + QStringLiteral("/tide-island");
    return QDir::homePath() + QStringLiteral("/.config/tide-island");
}

QString resolveUserConfigPath()
{
    return resolveUserConfigDir() + QStringLiteral("/userconfig.json");
}
}

SystemGlanceBackend *SystemGlanceBackend::s_instance = nullptr;

SystemGlanceBackend::SystemGlanceBackend(QObject *parent)
    : QObject(parent)
{
    s_instance = this;

    m_pollTimer.setInterval(1000);
    connect(&m_pollTimer, &QTimer::timeout, this, &SystemGlanceBackend::onPollTick);

    const QString cfgPath = resolveUserConfigPath();
    if (QFile::exists(cfgPath)) {
        m_configWatcher.addPath(cfgPath);
    }
    const QString cfgDir = resolveUserConfigDir();
    if (!QDir(cfgDir).exists()) {
        QDir().mkpath(cfgDir);
    }
    if (QDir(cfgDir).exists()) {
        m_configWatcher.addPath(cfgDir);
    }
    auto onConfigChanged = [this]() {
        reloadAvatar();
        const QString p = resolveUserConfigPath();
        if (QFile::exists(p) && !m_configWatcher.files().contains(p)) {
            m_configWatcher.addPath(p);
        }
        const QString d = resolveUserConfigDir();
        if (QDir(d).exists() && !m_configWatcher.directories().contains(d)) {
            m_configWatcher.addPath(d);
        }
    };
    connect(&m_configWatcher, &QFileSystemWatcher::fileChanged, this, onConfigChanged);
    connect(&m_configWatcher, &QFileSystemWatcher::directoryChanged, this, onConfigChanged);

    // Watch pacman log and local package database for transaction completions
    const QString pacmanLog = QStringLiteral("/var/log/pacman.log");
    if (QFile::exists(pacmanLog)) {
        m_lastPacmanLogTime = QFileInfo(pacmanLog).lastModified();
        m_pacmanWatcher.addPath(pacmanLog);
    }
    const QString pacmanLocalDir = QStringLiteral("/var/lib/pacman/local");
    if (QDir(pacmanLocalDir).exists()) {
        m_pacmanWatcher.addPath(pacmanLocalDir);
    }

    auto onPacmanTransaction = [this]() {
        const QString pLog = QStringLiteral("/var/log/pacman.log");
        if (QFile::exists(pLog)) {
            m_lastPacmanLogTime = QFileInfo(pLog).lastModified();
            if (!m_pacmanWatcher.files().contains(pLog)) {
                m_pacmanWatcher.addPath(pLog);
            }
        }
        // Invalidate cooldown so next check gets fresh counts immediately
        m_lastUpdateCheckTime = QElapsedTimer();
        if (m_active) {
            checkUpdatesAsync(true);
        }
    };
    connect(&m_pacmanWatcher, &QFileSystemWatcher::fileChanged, this, onPacmanTransaction);
    connect(&m_pacmanWatcher, &QFileSystemWatcher::directoryChanged, this, onPacmanTransaction);

    initStaticInfo();
}

SystemGlanceBackend::~SystemGlanceBackend()
{
    if (m_updateProcess && m_updateProcess->state() != QProcess::NotRunning) {
        m_updateProcess->kill();
        m_updateProcess->waitForFinished(300);
    }

    if (s_instance == this) {
        s_instance = nullptr;
    }
}

SystemGlanceBackend *SystemGlanceBackend::instance()
{
    return s_instance;
}

void SystemGlanceBackend::setActive(bool active)
{
    if (m_active == active)
        return;

    m_active = active;

    if (m_active) {
        reloadAvatar();

        // Check if pacman transactions occurred while glance was closed
        const QString pLog = QStringLiteral("/var/log/pacman.log");
        if (QFile::exists(pLog)) {
            const QDateTime curMtime = QFileInfo(pLog).lastModified();
            if (!m_lastPacmanLogTime.isValid() || curMtime > m_lastPacmanLogTime) {
                m_lastPacmanLogTime = curMtime;
                m_lastUpdateCheckTime = QElapsedTimer(); // Force fresh check
            }
        }

        checkUpdatesAsync();
        m_prevCpuTotal = 0;
        m_prevCpuIdle = 0;
        m_prevRxBytes = 0;
        m_prevTxBytes = 0;
        m_hasNetSample = false;
        m_lastNetTime.restart();

        refreshNow();
        m_pollTimer.start();
    } else {
        m_pollTimer.stop();
    }

    emit activeChanged(m_active);
}

void SystemGlanceBackend::refreshNow()
{
    updateCpu();
    updateMemory();
    updateGpu();
    updateDisk();
    updateNetwork();
    updateUptime();
    updateKernelStats();
    updateBatteryStats();

    emit statsUpdated();
}

void SystemGlanceBackend::onPollTick()
{
    if (!m_active)
        return;

    // Detect if pacman finished an update while glance is open (zero-overhead stat)
    const QString pLog = QStringLiteral("/var/log/pacman.log");
    if (QFile::exists(pLog)) {
        const QDateTime curMtime = QFileInfo(pLog).lastModified();
        if (m_lastPacmanLogTime.isValid() && curMtime > m_lastPacmanLogTime) {
            m_lastPacmanLogTime = curMtime;
            m_lastUpdateCheckTime = QElapsedTimer();
            checkUpdatesAsync(true);
        }
    }

    refreshNow();
}

void SystemGlanceBackend::initStaticInfo()
{
    m_userName = qEnvironmentVariable("USER");
    if (m_userName.isEmpty())
        m_userName = QStringLiteral("user");

    m_hostName = QHostInfo::localHostName();
    if (m_hostName.isEmpty())
        m_hostName = QStringLiteral("localhost");

    m_osName = QSysInfo::prettyProductName();
    if (m_osName.isEmpty())
        m_osName = QStringLiteral("Linux");

    m_kernelVersion = QSysInfo::kernelVersion();
    m_kernelRelease = m_kernelVersion;
    QFile osRelFile(QStringLiteral("/proc/sys/kernel/osrelease"));
    if (osRelFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString rel = QString::fromUtf8(osRelFile.readAll()).trimmed();
        if (!rel.isEmpty())
            m_kernelRelease = rel;
    }
    m_kernelArch = QSysInfo::currentCpuArchitecture();
    if (m_kernelArch.isEmpty())
        m_kernelArch = QStringLiteral("x86_64");

    // Resolve Avatar
    reloadAvatar();

    // Read CPU Model name from /proc/cpuinfo
    QFile cpuinfo(QStringLiteral("/proc/cpuinfo"));
    if (cpuinfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QByteArray content = cpuinfo.readAll();
        QTextStream in(content);
        while (!in.atEnd()) {
            const QString line = in.readLine();
            if (line.startsWith(QLatin1String("model name"), Qt::CaseInsensitive)) {
                const int colon = line.indexOf(QLatin1Char(':'));
                if (colon != -1) {
                    m_cpuModel = line.mid(colon + 1).trimmed();
                    // Clean up common verbose suffixes like "(R)" or "12th Gen"
                    m_cpuModel.replace(QStringLiteral("(R)"), QString());
                    m_cpuModel.replace(QStringLiteral("(TM)"), QString());
                    m_cpuModel.replace(QStringLiteral("CPU @"), QStringLiteral("@"));
                    m_cpuModel = m_cpuModel.simplified();
                    break;
                }
            }
        }
    }
    if (m_cpuModel.isEmpty()) {
        m_cpuModel = QStringLiteral("Generic Processor");
    }

    // Check GPU
    m_gpuAvailable = false;
    m_gpuName = QStringLiteral("Integrated Graphics");

    QDir drmDir(QStringLiteral("/sys/class/drm"));
    const QStringList cards = drmDir.entryList({QStringLiteral("card*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &card : cards) {
        if (card.contains(QLatin1Char('-'))) continue; // skip outputs like card1-DP-1

        const QString vendorPath = drmDir.absoluteFilePath(card) + QStringLiteral("/device/vendor");
        QFile vendorFile(vendorPath);
        if (vendorFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString vendor = QString::fromUtf8(vendorFile.readAll()).trimmed();
            m_gpuAvailable = true;
            m_gpuDrmCard = card;
            if (vendor == QLatin1String("0x8086")) {
                m_gpuName = QStringLiteral("Intel Graphics");
                break;
            } else if (vendor == QLatin1String("0x1002")) {
                m_gpuName = QStringLiteral("AMD Radeon");
                break;
            } else if (vendor == QLatin1String("0x10de")) {
                m_gpuName = QStringLiteral("NVIDIA GeForce");
                break;
            }
        }
    }

    emit staticInfoReady();
}

void SystemGlanceBackend::updateCpu()
{
    // 1. CPU Usage via /proc/stat
    QFile statFile(QStringLiteral("/proc/stat"));
    if (statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QByteArray line = statFile.readLine();
        if (line.startsWith("cpu ")) {
            quint64 user = 0, nice = 0, system = 0, idle = 0;
            quint64 iowait = 0, irq = 0, softirq = 0, steal = 0;

            const int matched = sscanf(line.constData() + 4,
                                       "%llu %llu %llu %llu %llu %llu %llu %llu",
                                       &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal);
            if (matched >= 4) {
                const quint64 total = user + nice + system + idle + iowait + irq + softirq + steal;
                const quint64 idleAll = idle + iowait;

                if (m_prevCpuTotal > 0 && total > m_prevCpuTotal) {
                    const quint64 diffTotal = total - m_prevCpuTotal;
                    const quint64 diffIdle = (idleAll >= m_prevCpuIdle) ? (idleAll - m_prevCpuIdle) : 0;
                    m_cpuUsage = qBound(0.0, (1.0 - static_cast<double>(diffIdle) / diffTotal) * 100.0, 100.0);
                }

                m_prevCpuTotal = total;
                m_prevCpuIdle = idleAll;
            }
        }
    }

    // 2. CPU Temperature via dedicated sensors (coretemp/k10temp/zenpower)
    const int detectedTemp = readCpuTemperature();
    if (detectedTemp > 0)
        m_cpuTemperature = detectedTemp;
}

void SystemGlanceBackend::updateMemory()
{
    quint64 memTotalKb = 0;
    quint64 memAvailKb = 0;
    quint64 swapTotalKb = 0;
    quint64 swapFreeKb = 0;

    QFile memFile(QStringLiteral("/proc/meminfo"));
    if (memFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QByteArray content = memFile.readAll();
        QTextStream in(content);
        while (!in.atEnd()) {
            const QString line = in.readLine();
            if (line.startsWith(QLatin1String("MemTotal:"))) {
                const auto parts = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
                if (parts.size() >= 2) memTotalKb = parts[1].toULongLong();
            } else if (line.startsWith(QLatin1String("MemAvailable:"))) {
                const auto parts = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
                if (parts.size() >= 2) memAvailKb = parts[1].toULongLong();
            } else if (line.startsWith(QLatin1String("SwapTotal:"))) {
                const auto parts = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
                if (parts.size() >= 2) swapTotalKb = parts[1].toULongLong();
            } else if (line.startsWith(QLatin1String("SwapFree:"))) {
                const auto parts = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
                if (parts.size() >= 2) swapFreeKb = parts[1].toULongLong();
            }
        }
    }

    if (memTotalKb == 0) {
        const long pages = sysconf(_SC_PHYS_PAGES);
        const long pageSize = sysconf(_SC_PAGE_SIZE);
        if (pages > 0 && pageSize > 0) {
            memTotalKb = static_cast<quint64>(pages) * static_cast<quint64>(pageSize) / 1024ULL;
        }
    }
    if (memAvailKb == 0) {
        const long avPages = sysconf(_SC_AVPHYS_PAGES);
        const long pageSize = sysconf(_SC_PAGE_SIZE);
        if (avPages > 0 && pageSize > 0) {
            memAvailKb = static_cast<quint64>(avPages) * static_cast<quint64>(pageSize) / 1024ULL;
        }
    }

    if (memTotalKb > 0) {
        const quint64 usedKb = (memTotalKb >= memAvailKb) ? (memTotalKb - memAvailKb) : 0;
        m_memoryTotalGb = static_cast<double>(memTotalKb) / (1024.0 * 1024.0);
        m_memoryUsedGb = static_cast<double>(usedKb) / (1024.0 * 1024.0);
        m_memoryUsagePercent = qBound(0.0, (static_cast<double>(usedKb) / memTotalKb) * 100.0, 100.0);
        m_memoryText = QString::asprintf("%.1f / %.1f GB", m_memoryUsedGb, m_memoryTotalGb);
    }

    if (swapTotalKb > 0) {
        const quint64 swapUsedKb = (swapTotalKb >= swapFreeKb) ? (swapTotalKb - swapFreeKb) : 0;
        m_swapTotalGb = static_cast<double>(swapTotalKb) / (1024.0 * 1024.0);
        m_swapUsedGb = static_cast<double>(swapUsedKb) / (1024.0 * 1024.0);
        m_swapUsagePercent = qBound(0.0, (static_cast<double>(swapUsedKb) / swapTotalKb) * 100.0, 100.0);
        m_swapText = QString::asprintf("%.1f / %.1f GB", m_swapUsedGb, m_swapTotalGb);
    } else {
        m_swapTotalGb = 0.0;
        m_swapUsedGb = 0.0;
        m_swapUsagePercent = 0.0;
        m_swapText = QStringLiteral("0 GB");
    }
}

void SystemGlanceBackend::updateGpu()
{
    if (!m_gpuAvailable) return;

    const QString cardName = m_gpuDrmCard.isEmpty() ? QStringLiteral("card0") : m_gpuDrmCard;

    // Check AMD GPU busy percent
    QFile amdBusy(QStringLiteral("/sys/class/drm/") + cardName + QStringLiteral("/device/gpu_busy_percent"));
    if (amdBusy.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool ok = false;
        const int val = QString::fromUtf8(amdBusy.readAll()).trimmed().toInt(&ok);
        if (ok) m_gpuUsage = qBound(0.0, static_cast<double>(val), 100.0);
    }

    // Read GPU temperature if available from drm card device hwmon
    QDir drmHwmon(QStringLiteral("/sys/class/drm/") + cardName + QStringLiteral("/device/hwmon"));
    if (drmHwmon.exists()) {
        const QStringList entries = drmHwmon.entryList({QStringLiteral("hwmon*")}, QDir::Dirs | QDir::NoDotAndDotDot);
        if (!entries.isEmpty()) {
            QFile tempF(drmHwmon.absoluteFilePath(entries.first()) + QStringLiteral("/temp1_input"));
            if (tempF.open(QIODevice::ReadOnly | QIODevice::Text)) {
                bool ok = false;
                const int raw = QString::fromUtf8(tempF.readAll()).trimmed().toInt(&ok);
                if (ok && raw > 1000)
                    m_gpuTemperature = raw / 1000;
            }
        }
    }

    // If integrated Intel GPU on same die, temperature mirrors package CPU temperature
    if (m_gpuTemperature <= 0 && m_gpuName.contains(QLatin1String("Intel"), Qt::CaseInsensitive)) {
        m_gpuTemperature = m_cpuTemperature;
    }
}

void SystemGlanceBackend::updateDisk()
{
    struct statvfs st;
    if (statvfs("/", &st) == 0) {
        const quint64 totalBytes = static_cast<quint64>(st.f_blocks) * st.f_frsize;
        const quint64 availBytes = static_cast<quint64>(st.f_bavail) * st.f_frsize;
        const quint64 usedBytes = (totalBytes >= availBytes) ? (totalBytes - availBytes) : 0;

        m_diskTotalGb = static_cast<double>(totalBytes) / (1024.0 * 1024.0 * 1024.0);
        m_diskUsedGb = static_cast<double>(usedBytes) / (1024.0 * 1024.0 * 1024.0);
        m_diskUsagePercent = totalBytes > 0 ? qBound(0.0, (static_cast<double>(usedBytes) / totalBytes) * 100.0, 100.0) : 0.0;
        m_diskText = QString::asprintf("%.0f / %.0f GB", m_diskUsedGb, m_diskTotalGb);
    }
}

void SystemGlanceBackend::updateNetwork()
{
    // Find active interface and IP
    QString primaryIface;
    QString primaryIp;
    bool vpn = false;

    const QList<QNetworkInterface> ifaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : ifaces) {
        const QString name = iface.name();
        if (name.startsWith(QLatin1String("tun")) || name.startsWith(QLatin1String("wg"))
            || name.startsWith(QLatin1String("proton")) || name.startsWith(QLatin1String("wireguard"))
            || name.startsWith(QLatin1String("tailscale"))) {
            vpn = true;
        }

        if (primaryIface.isEmpty() && (iface.flags() & QNetworkInterface::IsUp)
            && (iface.flags() & QNetworkInterface::IsRunning)
            && !(iface.flags() & QNetworkInterface::IsLoopBack)) {

            for (const QNetworkAddressEntry &entry : iface.addressEntries()) {
                if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol && !entry.ip().isLoopback()) {
                    primaryIface = name;
                    primaryIp = entry.ip().toString();
                    break;
                }
            }
        }
    }

    if (!primaryIface.isEmpty())
        m_networkInterface = primaryIface;
    if (!primaryIp.isEmpty())
        m_ipAddress = primaryIp;
    m_vpnActive = vpn;

    // Read cumulative rx and tx bytes from /proc/net/dev
    QFile netDev(QStringLiteral("/proc/net/dev"));
    if (netDev.open(QIODevice::ReadOnly | QIODevice::Text)) {
        quint64 totalRx = 0;
        quint64 totalTx = 0;

        const QByteArray content = netDev.readAll();
        QTextStream in(content);
        int lineNum = 0;
        while (!in.atEnd()) {
            const QString line = in.readLine();
            lineNum++;
            if (lineNum <= 2) continue; // Skip header lines

            const int colonIdx = line.indexOf(QLatin1Char(':'));
            if (colonIdx == -1) continue;

            const QString ifaceName = line.left(colonIdx).trimmed();
            if (ifaceName == QLatin1String("lo")) continue; // Skip loopback

            const auto tokens = line.mid(colonIdx + 1).split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
            if (tokens.size() >= 9) {
                const quint64 rx = tokens[0].toULongLong();
                const quint64 tx = tokens[8].toULongLong();
                totalRx += rx;
                totalTx += tx;
            }
        }

        if (m_hasNetSample && m_lastNetTime.isValid()) {
            const qint64 elapsedMs = m_lastNetTime.elapsed();
            if (elapsedMs > 200) {
                const double elapsedSec = elapsedMs / 1000.0;
                const quint64 deltaRx = (totalRx >= m_prevRxBytes) ? (totalRx - m_prevRxBytes) : 0;
                const quint64 deltaTx = (totalTx >= m_prevTxBytes) ? (totalTx - m_prevTxBytes) : 0;

                m_downloadBytesPerSec = static_cast<double>(deltaRx) / elapsedSec;
                m_uploadBytesPerSec = static_cast<double>(deltaTx) / elapsedSec;

                m_downloadSpeedText = QStringLiteral("↓ ") + formatSpeed(m_downloadBytesPerSec);
                m_uploadSpeedText = QStringLiteral("↑ ") + formatSpeed(m_uploadBytesPerSec);
            }
        }

        m_hasNetSample = true;
        m_prevRxBytes = totalRx;
        m_prevTxBytes = totalTx;
        m_lastNetTime.restart();
    }
}

void SystemGlanceBackend::updateUptime()
{
    QFile uptimeFile(QStringLiteral("/proc/uptime"));
    if (uptimeFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString content = QString::fromUtf8(uptimeFile.readAll()).trimmed();
        const auto parts = content.split(QLatin1Char(' '));
        if (!parts.isEmpty()) {
            bool ok = false;
            const double sec = parts[0].toDouble(&ok);
            if (ok && sec >= 0) {
                m_uptimeText = formatUptime(static_cast<quint64>(sec));
            }
        }
    }
}

QString SystemGlanceBackend::formatSpeed(double bytesPerSec)
{
    if (bytesPerSec < 1024.0)
        return QString::asprintf("%.0f B/s", bytesPerSec);
    if (bytesPerSec < 1024.0 * 1024.0)
        return QString::asprintf("%.1f KB/s", bytesPerSec / 1024.0);
    if (bytesPerSec < 1024.0 * 1024.0 * 1024.0)
        return QString::asprintf("%.1f MB/s", bytesPerSec / (1024.0 * 1024.0));
    return QString::asprintf("%.2f GB/s", bytesPerSec / (1024.0 * 1024.0 * 1024.0));
}

QString SystemGlanceBackend::formatUptime(quint64 uptimeSeconds)
{
    const quint64 days = uptimeSeconds / 86400;
    const quint64 hours = (uptimeSeconds % 86400) / 3600;
    const quint64 minutes = (uptimeSeconds % 3600) / 60;

    if (days > 0)
        return QStringLiteral("%1d %2h").arg(days).arg(hours);
    if (hours > 0)
        return QStringLiteral("%1h %2m").arg(hours).arg(minutes);
    return QStringLiteral("%1m").arg(minutes);
}

void SystemGlanceBackend::lockScreen()
{
    // Prefer Tide Island native lockscreen
    const QString tideIsland = QStandardPaths::findExecutable(QStringLiteral("tide-island"));
    if (!tideIsland.isEmpty()) {
        QProcess::startDetached(tideIsland, {QStringLiteral("--lock")});
        return;
    }

    // Try external lock helpers as fallback
    if (!QStandardPaths::findExecutable(QStringLiteral("hyprlock")).isEmpty()) {
        QProcess::startDetached(QStringLiteral("hyprlock"), {});
    } else if (!QStandardPaths::findExecutable(QStringLiteral("swaylock")).isEmpty()) {
        QProcess::startDetached(QStringLiteral("swaylock"), {});
    } else if (!QStandardPaths::findExecutable(QStringLiteral("waylock")).isEmpty()) {
        QProcess::startDetached(QStringLiteral("waylock"), {});
    } else {
        QProcess::startDetached(QStringLiteral("loginctl"), {QStringLiteral("lock-session")});
    }
}

void SystemGlanceBackend::suspendSystem()
{
    QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("suspend")});
}

void SystemGlanceBackend::rebootSystem()
{
    QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
}

void SystemGlanceBackend::powerOffSystem()
{
    QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("poweroff")});
}

void SystemGlanceBackend::setAvatarPath(const QString &path)
{
    QString clean = path.trimmed();
    if (clean.startsWith(QLatin1String("file://"))) {
        clean = QUrl(clean).toLocalFile();
    }
    const QString home = QDir::homePath();
    if (clean.startsWith(QLatin1String("~"))) {
        clean.replace(0, 1, home);
    }

    const QString nextAvatarUrl = clean.isEmpty() ? QString() : (QStringLiteral("file://") + clean);
    if (m_avatarPath != nextAvatarUrl) {
        m_avatarPath = nextAvatarUrl;
        emit avatarPathChanged();
        emit staticInfoReady();
    }

    // Persist to userconfig.json
    const QString cfgPath = resolveUserConfigPath();
    const QString cfgDir = resolveUserConfigDir();
    if (!QDir(cfgDir).exists()) {
        QDir().mkpath(cfgDir);
    }
    QFile file(cfgPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    if (clean.isEmpty()) {
        obj.remove(QStringLiteral("avatarPath"));
    } else {
        obj.insert(QStringLiteral("avatarPath"), clean);
    }
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

void SystemGlanceBackend::openAvatarDirectory()
{
    QString dir = QDir::homePath() + QStringLiteral("/Pictures");
    if (!m_avatarPath.isEmpty()) {
        QString local = m_avatarPath;
        if (local.startsWith(QLatin1String("file://"))) {
            local = QUrl(local).toLocalFile();
        }
        QFileInfo fi(local);
        if (fi.exists()) {
            dir = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
        }
    }
    QProcess::startDetached(QStringLiteral("xdg-open"), {dir});
}

void SystemGlanceBackend::updateKernelStats()
{
    // Read /proc/loadavg
    QFile loadFile(QStringLiteral("/proc/loadavg"));
    if (loadFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString line = QString::fromUtf8(loadFile.readLine()).trimmed();
        const QStringList parts = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (parts.size() >= 4) {
            bool ok1 = false, ok5 = false, ok15 = false;
            m_loadAvg1 = parts[0].toDouble(&ok1);
            m_loadAvg5 = parts[1].toDouble(&ok5);
            m_loadAvg15 = parts[2].toDouble(&ok15);
            m_loadAvgText = QStringLiteral("%1, %2, %3").arg(parts[0], parts[1], parts[2]);

            const QStringList taskParts = parts[3].split(QLatin1Char('/'));
            if (taskParts.size() >= 2) {
                m_runningTasks = taskParts[0].toInt();
                m_totalTasks = taskParts[1].toInt();
                m_tasksText = QStringLiteral("%1 running • %2 tasks").arg(m_runningTasks).arg(m_totalTasks);
            }
        }
    }

    // Read CPU scaling governor
    QFile govFile(QStringLiteral("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"));
    if (govFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_cpuGovernor = QString::fromUtf8(govFile.readAll()).trimmed();
    } else {
        m_cpuGovernor = QStringLiteral("powersave");
    }
}

void SystemGlanceBackend::updateBatteryStats()
{
    QDir dir(QStringLiteral("/sys/class/power_supply"));
    const QStringList batteries = dir.entryList({QStringLiteral("BAT*"), QStringLiteral("battery*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    if (batteries.isEmpty()) {
        m_hasBattery = false;
        return;
    }

    m_hasBattery = true;
    const QString batPath = dir.absoluteFilePath(batteries.first());

    // Status
    QFile statusFile(batPath + QStringLiteral("/status"));
    if (statusFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_batteryStatus = QString::fromUtf8(statusFile.readAll()).trimmed();
    }

    // Capacity
    QFile capFile(batPath + QStringLiteral("/capacity"));
    if (capFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool ok = false;
        int cap = QString::fromUtf8(capFile.readAll()).trimmed().toInt(&ok);
        if (ok) m_batteryCapacity = cap;
    }

    // Power now / Watts
    double watts = 0.0;
    QFile powerFile(batPath + QStringLiteral("/power_now"));
    if (powerFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool ok = false;
        qint64 uW = QString::fromUtf8(powerFile.readAll()).trimmed().toLongLong(&ok);
        if (ok && uW > 0) {
            watts = uW / 1000000.0;
        }
    } else {
        QFile currFile(batPath + QStringLiteral("/current_now"));
        QFile voltFile(batPath + QStringLiteral("/voltage_now"));
        if (currFile.open(QIODevice::ReadOnly | QIODevice::Text) && voltFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            bool okC = false, okV = false;
            qint64 uA = QString::fromUtf8(currFile.readAll()).trimmed().toLongLong(&okC);
            qint64 uV = QString::fromUtf8(voltFile.readAll()).trimmed().toLongLong(&okV);
            if (okC && okV && uA > 0 && uV > 0) {
                watts = (static_cast<double>(uA) * static_cast<double>(uV)) / 1000000000000.0;
            }
        }
    }
    m_batteryPowerWatts = watts;

    // Cycle count
    QFile cycleFile(batPath + QStringLiteral("/cycle_count"));
    if (cycleFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool ok = false;
        int cyc = QString::fromUtf8(cycleFile.readAll()).trimmed().toInt(&ok);
        if (ok) m_batteryCycleCount = cyc;
    }

    // Health percent
    qint64 full = 0, fullDesign = 0;
    QFile efFile(batPath + QStringLiteral("/energy_full"));
    QFile efdFile(batPath + QStringLiteral("/energy_full_design"));
    if (efFile.open(QIODevice::ReadOnly | QIODevice::Text) && efdFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        full = QString::fromUtf8(efFile.readAll()).trimmed().toLongLong();
        fullDesign = QString::fromUtf8(efdFile.readAll()).trimmed().toLongLong();
    } else {
        QFile cfFile(batPath + QStringLiteral("/charge_full"));
        QFile cfdFile(batPath + QStringLiteral("/charge_full_design"));
        if (cfFile.open(QIODevice::ReadOnly | QIODevice::Text) && cfdFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            full = QString::fromUtf8(cfFile.readAll()).trimmed().toLongLong();
            fullDesign = QString::fromUtf8(cfdFile.readAll()).trimmed().toLongLong();
        }
    }
    if (full > 0 && fullDesign > 0) {
        m_batteryHealthPercent = std::clamp(static_cast<int>(qRound(100.0 * full / fullDesign)), 0, 100);
    }

    // Conservation mode
    const QString ideapadPath = QStringLiteral("/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode");
    const QString ideapadPlatform = QStringLiteral("/sys/devices/platform/ideapad_acpi/conservation_mode");
    QString cmPath;
    if (QFile::exists(ideapadPath)) cmPath = ideapadPath;
    else if (QFile::exists(ideapadPlatform)) cmPath = ideapadPlatform;

    if (!cmPath.isEmpty()) {
        QFile cmFile(cmPath);
        if (cmFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            m_batteryConservationActive = (QString::fromUtf8(cmFile.readAll()).trimmed() == QStringLiteral("1"));
        }
    }

    // Rate text
    if (m_batteryStatus.compare(QStringLiteral("Charging"), Qt::CaseInsensitive) == 0) {
        m_batteryRateText = watts > 0.05 ? QString::asprintf("+%.1f W", watts) : QStringLiteral("Charging");
    } else if (m_batteryStatus.compare(QStringLiteral("Discharging"), Qt::CaseInsensitive) == 0) {
        m_batteryRateText = watts > 0.05 ? QString::asprintf("-%.1f W", watts) : QStringLiteral("Discharging");
    } else if (m_batteryStatus.compare(QStringLiteral("Not charging"), Qt::CaseInsensitive) == 0) {
        m_batteryRateText = m_batteryConservationActive ? QStringLiteral("Capped") : QStringLiteral("Plugged In");
    } else if (m_batteryStatus.compare(QStringLiteral("Full"), Qt::CaseInsensitive) == 0) {
        m_batteryRateText = QStringLiteral("Full");
    } else {
        m_batteryRateText = watts > 0.05 ? QString::asprintf("%.1f W", watts) : m_batteryStatus;
    }
}

int SystemGlanceBackend::readCpuTemperature()
{
    QDir hwmonBase(QStringLiteral("/sys/class/hwmon"));
    const QStringList hwmons = hwmonBase.entryList({QStringLiteral("hwmon*")}, QDir::Dirs | QDir::NoDotAndDotDot);

    // Priorities for CPU hwmon drivers:
    // 1. coretemp (Intel), k10temp (AMD), zenpower (AMD)
    // 2. cpu_thermal, soc_thermal (ARM / SoC)
    const QStringList highPriorityDrivers = {
        QStringLiteral("coretemp"),
        QStringLiteral("k10temp"),
        QStringLiteral("zenpower"),
        QStringLiteral("cpu_thermal"),
        QStringLiteral("soc_thermal")
    };

    // First pass: High-priority dedicated CPU sensor drivers
    for (const QString &driverName : highPriorityDrivers) {
        for (const QString &h : hwmons) {
            const QString hPath = hwmonBase.absoluteFilePath(h);
            QFile nameFile(hPath + QStringLiteral("/name"));
            if (!nameFile.open(QIODevice::ReadOnly | QIODevice::Text))
                continue;

            const QString name = QString::fromUtf8(nameFile.readAll()).trimmed().toLower();
            if (name == driverName) {
                int packageTemp = 0;
                int maxCoreTemp = 0;

                QDir hDir(hPath);
                const QStringList inputs = hDir.entryList({QStringLiteral("temp*_input")}, QDir::Files);
                for (const QString &input : inputs) {
                    QFile tempFile(hDir.absoluteFilePath(input));
                    if (!tempFile.open(QIODevice::ReadOnly | QIODevice::Text))
                        continue;

                    bool ok = false;
                    const int raw = QString::fromUtf8(tempFile.readAll()).trimmed().toInt(&ok);
                    if (!ok || raw < 1000 || raw > 130000)
                        continue;

                    const int deg = raw / 1000;
                    if (deg > maxCoreTemp)
                        maxCoreTemp = deg;

                    // Check for label like "Package id 0", "Tdie", "Tctl"
                    const QString base = input.left(input.length() - 6);
                    QFile labelFile(hDir.absoluteFilePath(base + QStringLiteral("_label")));
                    if (labelFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                        const QString label = QString::fromUtf8(labelFile.readAll()).trimmed().toLower();
                        if (label.contains(QLatin1String("package")) ||
                            label.contains(QLatin1String("tdie")) ||
                            label.contains(QLatin1String("tctl"))) {
                            packageTemp = deg;
                        }
                    }
                }

                if (packageTemp > 0)
                    return packageTemp;
                if (maxCoreTemp > 0)
                    return maxCoreTemp;
            }
        }
    }

    // Second pass: thermal_zone with type x86_pkg_temp or cpu
    QDir tzBase(QStringLiteral("/sys/class/thermal"));
    const QStringList zones = tzBase.entryList({QStringLiteral("thermal_zone*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &z : zones) {
        const QString zPath = tzBase.absoluteFilePath(z);
        QFile typeFile(zPath + QStringLiteral("/type"));
        if (!typeFile.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;

        const QString type = QString::fromUtf8(typeFile.readAll()).trimmed().toLower();
        if (type == QLatin1String("x86_pkg_temp") || type.contains(QLatin1String("cpu")) || type.contains(QLatin1String("tcpu"))) {
            QFile tempFile(zPath + QStringLiteral("/temp"));
            if (tempFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                bool ok = false;
                const int raw = QString::fromUtf8(tempFile.readAll()).trimmed().toInt(&ok);
                if (ok && raw > 1000 && raw < 130000)
                    return raw / 1000;
            }
        }
    }

    // Third pass: Fallback to acpitz or thermal_zone0
    for (const QString &h : hwmons) {
        const QString hPath = hwmonBase.absoluteFilePath(h);
        QFile nameFile(hPath + QStringLiteral("/name"));
        if (!nameFile.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;

        const QString name = QString::fromUtf8(nameFile.readAll()).trimmed().toLower();
        if (name == QLatin1String("acpitz")) {
            QFile tempFile(hPath + QStringLiteral("/temp1_input"));
            if (tempFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                bool ok = false;
                const int raw = QString::fromUtf8(tempFile.readAll()).trimmed().toInt(&ok);
                if (ok && raw > 1000 && raw < 130000)
                    return raw / 1000;
            }
        }
    }

    QFile tz0(QStringLiteral("/sys/class/thermal/thermal_zone0/temp"));
    if (tz0.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool ok = false;
        const int raw = QString::fromUtf8(tz0.readAll()).trimmed().toInt(&ok);
        if (ok && raw > 1000 && raw < 130000)
            return raw / 1000;
    }

    return 0;
}

void SystemGlanceBackend::reloadAvatar()
{
    const QString home = QDir::homePath();
    QString resolvedAvatar;

    // 1. Check userconfig.json
    const QString cfgPath = resolveUserConfigPath();
    QFile cfgFile(cfgPath);
    if (cfgFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QJsonDocument doc = QJsonDocument::fromJson(cfgFile.readAll());
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            QString configured = obj.value(QStringLiteral("avatarPath")).toString();
            if (configured.isEmpty()) {
                configured = obj.value(QStringLiteral("displayPicture")).toString();
            }
            if (!configured.isEmpty()) {
                if (configured.startsWith(QLatin1String("~"))) configured.replace(0, 1, home);
                if (configured.startsWith(QLatin1String("file://"))) configured = QUrl(configured).toLocalFile();
                if (QFileInfo::exists(configured)) {
                    resolvedAvatar = configured;
                }
            }
        }
    }

    // 2. Check ChillPill-Shell config for fallback
    if (resolvedAvatar.isEmpty()) {
        const QString xdgConfig = qEnvironmentVariable("XDG_CONFIG_HOME").trimmed();
        const QString cpConfigDir = !xdgConfig.isEmpty() ? (xdgConfig + QStringLiteral("/chillpill-shell")) : (home + QStringLiteral("/.config/chillpill-shell"));
        QFile cpFile(cpConfigDir + QStringLiteral("/config.jsonc"));
        if (cpFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString cpText = QString::fromUtf8(cpFile.readAll());
            cpText.replace(QRegularExpression(QStringLiteral("/\\*.*?\\*/"), QRegularExpression::DotMatchesEverythingOption), QString());
            const QStringList lines = cpText.split(u'\n');
            QStringList stripped;
            for (const QString &l : lines) {
                const int commentIdx = l.indexOf(QStringLiteral("//"));
                stripped.append(commentIdx >= 0 ? l.left(commentIdx) : l);
            }
            const QJsonDocument cpDoc = QJsonDocument::fromJson(stripped.join(u'\n').toUtf8());
            if (cpDoc.isObject()) {
                QString cpPic = cpDoc.object().value(QStringLiteral("displayPicture")).toString();
                if (!cpPic.isEmpty()) {
                    if (cpPic.startsWith(QLatin1String("~"))) cpPic.replace(0, 1, home);
                    if (cpPic.startsWith(QLatin1String("file://"))) cpPic = QUrl(cpPic).toLocalFile();
                    if (QFileInfo::exists(cpPic)) {
                        resolvedAvatar = cpPic;
                    }
                }
            }
        }
    }

    // 3. Check common locations
    if (resolvedAvatar.isEmpty()) {
        const QString tideCfgDir = resolveUserConfigDir();
        const QStringList candidates = {
            tideCfgDir + QStringLiteral("/avatar.png"),
            tideCfgDir + QStringLiteral("/avatar.jpg"),
            tideCfgDir + QStringLiteral("/avatar.jpeg"),
            home + QStringLiteral("/.pfp.png"),
            home + QStringLiteral("/.pfp.jpg"),
            home + QStringLiteral("/.pfp.jpeg"),
            home + QStringLiteral("/.pfp"),
            home + QStringLiteral("/.face"),
            home + QStringLiteral("/.face.icon"),
            home + QStringLiteral("/.avatar.png"),
            home + QStringLiteral("/.avatar.jpg")
        };
        for (const QString &cand : candidates) {
            if (QFileInfo::exists(cand)) {
                resolvedAvatar = cand;
                break;
            }
        }
    }

    const QString nextAvatarUrl = resolvedAvatar.isEmpty() ? QString() : (QStringLiteral("file://") + resolvedAvatar);
    if (m_avatarPath != nextAvatarUrl) {
        m_avatarPath = nextAvatarUrl;
        emit avatarPathChanged();
    }
}

void SystemGlanceBackend::checkUpdatesAsync(bool force)
{
    if (m_checkingUpdates)
        return;

    // Rate limit checks to once every 10 minutes unless explicitly forced or pacman log changed
    if (!force && m_lastUpdateCheckTime.isValid() && m_lastUpdateCheckTime.elapsed() < 600000)
        return;

    // If pacman is currently holding the database lock (update in progress), wait until it finishes
    if (QFile::exists(QStringLiteral("/var/lib/pacman/db.lck")))
        return;

    m_checkingUpdates = true;
    emit updatesChanged();

    // Clean any stale lock left by an abruptly terminated checkupdates run
    const QString lckPath = QStringLiteral("/tmp/checkup-db-") + QString::number(getuid()) + QStringLiteral("/db.lck");
    QFile::remove(lckPath);

    QProcess *proc = new QProcess(this);
    m_updateProcess = proc;

    auto onFinished = [this, proc](int exitCode, QProcess::ExitStatus exitStatus) {
        m_checkingUpdates = false;
        m_lastUpdateCheckTime.restart();

        const QByteArray stdOut = proc->readAllStandardOutput();

        if (exitStatus == QProcess::NormalExit && exitCode == 0) {
            const QString text = QString::fromUtf8(stdOut).trimmed();
            m_pendingUpdatesCount = text.isEmpty() ? 0 : text.split(QLatin1Char('\n'), Qt::SkipEmptyParts).size();
        } else if (exitStatus == QProcess::NormalExit && exitCode == 2) {
            // checkupdates returns 2 when no updates are available
            m_pendingUpdatesCount = 0;
        } else {
            // Fallback: check local synced pacman database with pacman -Qu
            QProcess pacProc;
            pacProc.start(QStringLiteral("/usr/bin/pacman"), {QStringLiteral("-Qu")});
            if (pacProc.waitForFinished(2000)) {
                if (pacProc.exitCode() == 0) {
                    const QString fallbackText = QString::fromUtf8(pacProc.readAllStandardOutput()).trimmed();
                    m_pendingUpdatesCount = fallbackText.isEmpty() ? 0 : fallbackText.split(QLatin1Char('\n'), Qt::SkipEmptyParts).size();
                } else {
                    // pacman -Qu exits with 1 when no updates are found
                    m_pendingUpdatesCount = 0;
                }
            }
        }

        emit updatesChanged();
        emit statsUpdated();
        proc->deleteLater();
    };

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, onFinished);

    connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError) {
        // Fallback: check local synced pacman database on error
        QProcess pacProc;
        pacProc.start(QStringLiteral("/usr/bin/pacman"), {QStringLiteral("-Qu")});
        if (pacProc.waitForFinished(2000)) {
            if (pacProc.exitCode() == 0) {
                const QString fallbackText = QString::fromUtf8(pacProc.readAllStandardOutput()).trimmed();
                m_pendingUpdatesCount = fallbackText.isEmpty() ? 0 : fallbackText.split(QLatin1Char('\n'), Qt::SkipEmptyParts).size();
            } else {
                m_pendingUpdatesCount = 0;
            }
        }

        m_checkingUpdates = false;
        m_lastUpdateCheckTime.restart();
        emit updatesChanged();
        emit statsUpdated();
        proc->deleteLater();
    });

    if (QFile::exists(QStringLiteral("/usr/bin/checkupdates"))) {
        proc->start(QStringLiteral("/usr/bin/checkupdates"), QStringList());
    } else if (QFile::exists(QStringLiteral("/usr/bin/pacman"))) {
        proc->start(QStringLiteral("/usr/bin/pacman"), {QStringLiteral("-Qu")});
    } else {
        m_checkingUpdates = false;
        emit updatesChanged();
        emit statsUpdated();
        proc->deleteLater();
    }
}

void SystemGlanceBackend::launchUpdateTerminal()
{
    // Invalidate cooldown timer so that subsequent check gets fresh post-update data
    m_lastUpdateCheckTime = QElapsedTimer();

    QString term;
    const QString envTerm = qEnvironmentVariable("TERMINAL").trimmed();
    if (!envTerm.isEmpty()) {
        term = envTerm;
    } else {
        const QStringList candidates = {
            QStringLiteral("kitty"),
            QStringLiteral("foot"),
            QStringLiteral("alacritty"),
            QStringLiteral("wezterm"),
            QStringLiteral("ghostty"),
            QStringLiteral("konsole"),
            QStringLiteral("gnome-terminal"),
            QStringLiteral("xfce4-terminal"),
            QStringLiteral("xterm")
        };
        for (const QString &c : candidates) {
            if (!QStandardPaths::findExecutable(c).isEmpty()) {
                term = c;
                break;
            }
        }
    }
    if (term.isEmpty())
        term = QStringLiteral("xterm");

    const QString updateCmd = QFile::exists(QStringLiteral("/usr/bin/yay"))
        ? QStringLiteral("yay; echo; read -n 1 -s -r -p 'Press any key to close...'")
        : QStringLiteral("sudo pacman -Syu; echo; read -n 1 -s -r -p 'Press any key to close...'");

    QStringList args;
    const QString binName = QFileInfo(term).fileName().toLower();
    if (binName == QLatin1String("foot")) {
        args = {QStringLiteral("sh"), QStringLiteral("-c"), updateCmd};
    } else if (binName == QLatin1String("gnome-terminal")) {
        args = {QStringLiteral("--"), QStringLiteral("sh"), QStringLiteral("-c"), updateCmd};
    } else {
        args = {QStringLiteral("-e"), QStringLiteral("sh"), QStringLiteral("-c"), updateCmd};
    }

    QProcess::startDetached(term, args);
}
