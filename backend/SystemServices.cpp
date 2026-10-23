#include "SystemServices.h"
#include "UserConfigBackend.h"
#include "ScreenRecorderController.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <QFutureWatcher>
#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>
#include <QtConcurrent/QtConcurrent>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QDBusMessage>
#include <QClipboard>
#include <QGuiApplication>
#include <QLocalSocket>

#ifdef Q_OS_UNIX
#include <unistd.h>
#endif

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

constexpr qsizetype kMaximumStreamBufferBytes = 64 * 1024;

struct ThumbnailResult {
    QString sourcePath;
    QString cachePath;
    bool cacheAvailable = false;
    bool updated = false;
    QString errorString;
};

QString thumbnailMetadataPath(const QString &cachePath) {
    return cachePath + QStringLiteral(".meta.json");
}

QJsonObject thumbnailMetadata(const QFileInfo &sourceInfo,
                              int targetWidth,
                              int targetHeight,
                              int quality) {
    return {
        {QStringLiteral("sourcePath"), sourceInfo.absoluteFilePath()},
        {QStringLiteral("sourceModifiedMs"), sourceInfo.lastModified().toMSecsSinceEpoch()},
        {QStringLiteral("sourceSize"), sourceInfo.size()},
        {QStringLiteral("targetWidth"), targetWidth},
        {QStringLiteral("targetHeight"), targetHeight},
        {QStringLiteral("quality"), quality}
    };
}

bool thumbnailMetadataMatches(const QString &cachePath, const QJsonObject &expected) {
    if (!QFileInfo::exists(cachePath)) return false;

    QFile metadataFile(thumbnailMetadataPath(cachePath));
    if (!metadataFile.open(QIODevice::ReadOnly)) return false;

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(metadataFile.readAll(), &parseError);
    return parseError.error == QJsonParseError::NoError
        && document.isObject()
        && document.object() == expected;
}

bool writeThumbnailMetadata(const QString &cachePath, const QJsonObject &metadata, QString *errorString) {
    QSaveFile metadataFile(thumbnailMetadataPath(cachePath));
    if (!metadataFile.open(QIODevice::WriteOnly)) {
        if (errorString) *errorString = metadataFile.errorString();
        return false;
    }

    if (metadataFile.write(QJsonDocument(metadata).toJson(QJsonDocument::Compact)) < 0
        || !metadataFile.commit()) {
        if (errorString) *errorString = metadataFile.errorString();
        return false;
    }

    return true;
}

ThumbnailResult createWallpaperThumbnail(const QString &sourcePath,
                                         const QString &cachePath,
                                         const QString &cacheDir,
                                         int targetWidth,
                                         int targetHeight,
                                         int quality) {
    ThumbnailResult result;
    result.sourcePath = sourcePath;
    result.cachePath = cachePath;

    if (sourcePath.isEmpty() || cachePath.isEmpty() || cacheDir.isEmpty()) {
        result.errorString = QStringLiteral("Missing wallpaper thumbnail path.");
        return result;
    }

    if (targetWidth <= 0 || targetHeight <= 0) {
        result.errorString = QStringLiteral("Invalid wallpaper thumbnail size.");
        return result;
    }

    const QFileInfo sourceInfo(sourcePath);
    if (!sourceInfo.exists() || !sourceInfo.isFile()) {
        result.errorString = QStringLiteral("Wallpaper source file does not exist.");
        return result;
    }

    if (!QDir().mkpath(cacheDir)) {
        result.errorString = QStringLiteral("Could not create wallpaper cache directory.");
        return result;
    }

    const int boundedQuality = std::clamp(quality, 1, 100);
    const QJsonObject expectedMetadata = thumbnailMetadata(
        sourceInfo,
        targetWidth,
        targetHeight,
        boundedQuality
    );
    if (thumbnailMetadataMatches(cachePath, expectedMetadata)) {
        result.cacheAvailable = true;
        return result;
    }

    QImageReader reader(sourcePath);
    reader.setAutoTransform(true);
    const QSize sourceSize = reader.size();
    const QSize requestedSize(targetWidth, targetHeight);
    if (sourceSize.isValid()) {
        const QSize decodeSize = sourceSize.scaled(requestedSize, Qt::KeepAspectRatioByExpanding);
        if (qint64(decodeSize.width()) * decodeSize.height()
                < qint64(sourceSize.width()) * sourceSize.height()) {
            reader.setScaledSize(decodeSize);
        }
    }
    const QImage sourceImage = reader.read();
    if (sourceImage.isNull()) {
        result.errorString = reader.errorString().isEmpty()
            ? QStringLiteral("Could not read wallpaper source image.")
            : reader.errorString();
        return result;
    }

    const QSize targetSize(targetWidth, targetHeight);
    const QImage scaled = sourceImage.scaled(targetSize, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    const int cropX = std::max(0, (scaled.width() - targetWidth) / 2);
    const int cropY = std::max(0, (scaled.height() - targetHeight) / 2);
    const QImage cropped = scaled.copy(cropX, cropY, targetWidth, targetHeight);

    QSaveFile output(cachePath);
    if (!output.open(QIODevice::WriteOnly)) {
        result.errorString = output.errorString();
        return result;
    }

    QImageWriter writer(&output, "jpg");
    writer.setQuality(boundedQuality);
    if (!writer.write(cropped)) {
        result.errorString = writer.errorString().isEmpty()
            ? QStringLiteral("Could not write wallpaper thumbnail.")
            : writer.errorString();
        output.cancelWriting();
        return result;
    }

    if (!output.commit()) {
        result.errorString = output.errorString();
        return result;
    }

    result.cacheAvailable = QFileInfo::exists(cachePath);
    result.updated = result.cacheAvailable;
    if (result.cacheAvailable)
        writeThumbnailMetadata(cachePath, expectedMetadata, &result.errorString);
    return result;
}

QString trimCommandOutput(const QByteArray &stdoutData, const QByteArray &stderrData) {
    QString output = QString::fromUtf8(stdoutData).trimmed();
    const QString stderrOutput = QString::fromUtf8(stderrData).trimmed();
    if (!stderrOutput.isEmpty()) {
        if (!output.isEmpty()) output += QLatin1Char('\n');
        output += stderrOutput;
    }
    return output;
}

static SystemServices *s_systemServicesInstance = nullptr;

} // namespace

SystemServices::SystemServices(QObject *parent)
    : QObject(parent) {
    s_systemServicesInstance = this;
    m_cavaLevels = QVariantList{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};

    m_notificationRestartTimer.setSingleShot(true);
    m_notificationRestartTimer.setInterval(1200);
    connect(&m_notificationRestartTimer, &QTimer::timeout, this, &SystemServices::startNotificationMonitor);

    m_pipeWireRestartTimer.setSingleShot(true);
    m_pipeWireRestartTimer.setInterval(1200);
    connect(&m_pipeWireRestartTimer, &QTimer::timeout, this, &SystemServices::startPipeWireMonitor);

    m_recordingPortalRestartTimer.setSingleShot(true);
    m_recordingPortalRestartTimer.setInterval(1200);
    connect(&m_recordingPortalRestartTimer, &QTimer::timeout, this, &SystemServices::startRecordingPortalMonitor);

    m_recordingSnapshotDebounceTimer.setSingleShot(true);
    m_recordingSnapshotDebounceTimer.setInterval(250);
    connect(&m_recordingSnapshotDebounceTimer, &QTimer::timeout, this, &SystemServices::requestPrivacySnapshot);
    QTimer::singleShot(200, this, &SystemServices::requestPrivacySnapshot);

    m_privacyPollTimer.setInterval(25000);
    connect(&m_privacyPollTimer, &QTimer::timeout, this, &SystemServices::requestPrivacySnapshot);
    m_privacyPollTimer.start();

    m_cavaRestartTimer.setSingleShot(true);
    m_cavaRestartTimer.setInterval(1200);
    connect(&m_cavaRestartTimer, &QTimer::timeout, this, &SystemServices::startCava);

    m_brightnessThrottleTimer.setSingleShot(true);
    connect(&m_brightnessThrottleTimer, &QTimer::timeout, this, [this]() {
        if (m_pendingBrightness >= 0.0 && (m_lastAppliedBrightness < 0.0 || std::abs(m_pendingBrightness - m_lastAppliedBrightness) >= 0.005)) {
            applyPendingBrightness();
        }
    });

    m_volumeThrottleTimer.setSingleShot(true);
    connect(&m_volumeThrottleTimer, &QTimer::timeout, this, [this]() {
        if (m_pendingVolume >= 0.0 && (m_lastAppliedVolume < 0.0 || std::abs(m_pendingVolume - m_lastAppliedVolume) >= 0.005)) {
            applyPendingVolume();
        }
    });

    m_micVolumeThrottleTimer.setSingleShot(true);
    connect(&m_micVolumeThrottleTimer, &QTimer::timeout, this, [this]() {
        if (m_pendingMicVolume >= 0.0 && (m_lastAppliedMicVolume < 0.0 || std::abs(m_pendingMicVolume - m_lastAppliedMicVolume) >= 0.005)) {
            applyPendingMicVolume();
        }
    });

    startNotificationMonitor();
    startPipeWireMonitor();
    startRecordingPortalMonitor();
    requestScreenRecordingSnapshot();
    detectBatteryThresholdSupport();
    requestBatteryThresholdState();
}

SystemServices::~SystemServices() {
    if (s_systemServicesInstance == this)
        s_systemServicesInstance = nullptr;

    m_shuttingDown = true;
    m_notificationRestartTimer.stop();
    m_pipeWireRestartTimer.stop();
    m_recordingPortalRestartTimer.stop();
    m_recordingSnapshotDebounceTimer.stop();
    m_cavaRestartTimer.stop();
    m_brightnessThrottleTimer.stop();
    m_volumeThrottleTimer.stop();
    m_micVolumeThrottleTimer.stop();
    m_pendingAppStreamVolumePercents.clear();
    m_activeAppStreamVolumeCommands.clear();

    stopProcess(m_notificationMonitor);
    stopProcess(m_pipeWireMonitor);
    stopProcess(m_recordingPortalMonitor);
    stopProcess(m_recordingSnapshot);
    stopProcess(m_tlpSetter);
    stopCava();
}

SystemServices *SystemServices::instance() {
    return s_systemServicesInstance;
}

bool SystemServices::screenRecordingActive() const {
    return m_screenRecordingActive;
}

QVariantList SystemServices::cavaLevels() const {
    return m_cavaLevels;
}

QString SystemServices::findExecutable(const QString &program) const {
    if (program.contains(QLatin1Char('/'))) {
        const QFileInfo fileInfo(program);
        return fileInfo.exists() && fileInfo.isExecutable() ? fileInfo.absoluteFilePath() : QString();
    }

    return QStandardPaths::findExecutable(program);
}

QProcess *SystemServices::startCommand(const QString &program,
                                       const QStringList &arguments,
                                       int timeoutMs,
                                       CommandCallback callback,
                                       const QByteArray &stdinData) {
    const QString executable = findExecutable(program);
    if (executable.isEmpty()) {
        CommandResult result;
        result.errorString = QStringLiteral("%1 is not installed.").arg(program);
        QTimer::singleShot(0, this, [callback, result]() {
            callback(result);
        });
        return nullptr;
    }

    auto *process = new QProcess(this);
    process->setProgram(executable);
    process->setArguments(arguments);
    process->setProcessChannelMode(QProcess::SeparateChannels);

    auto completed = std::make_shared<bool>(false);
    auto timedOut = std::make_shared<bool>(false);
    auto finish = [process, callback, completed, timedOut](const QString &errorString = QString()) {
        if (*completed) return;
        *completed = true;

        CommandResult result;
        result.exitCode = process->exitCode();
        result.exitStatus = process->exitStatus();
        result.stdoutData = process->readAllStandardOutput();
        result.stderrData = process->readAllStandardError();
        result.errorString = errorString;
        result.timedOut = *timedOut;
        if (result.errorString.isEmpty() && result.timedOut)
            result.errorString = QStringLiteral("Command timed out.");
        if (result.errorString.isEmpty() && process->error() != QProcess::UnknownError)
            result.errorString = process->errorString();

        if (callback)
            callback(result);
        process->deleteLater();
    };

    auto *timeout = new QTimer(process);
    timeout->setSingleShot(true);
    connect(timeout, &QTimer::timeout, process, [process, timedOut]() {
        *timedOut = true;
        process->kill();
    });

    connect(process, &QProcess::started, process, [process, timeoutMs, timeout, stdinData]() {
        if (timeoutMs > 0)
            timeout->start(timeoutMs);
        if (!stdinData.isEmpty()) {
            process->write(stdinData);
            process->closeWriteChannel();
        }
    });

    connect(process, &QProcess::errorOccurred, process, [finish](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            finish(QStringLiteral("Command failed to start."));
    });

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            process, [timeout, finish](int, QProcess::ExitStatus) {
        timeout->stop();
        finish();
    });

    process->start();
    return process;
}

QString SystemServices::commandErrorText(const QString &program, const CommandResult &result) const {
    if (!result.errorString.isEmpty())
        return result.errorString;
    if (result.exitStatus == QProcess::CrashExit)
        return QStringLiteral("%1 crashed.").arg(program);
    if (result.exitCode != 0) {
        const QString output = trimCommandOutput(result.stdoutData, result.stderrData);
        return output.isEmpty()
            ? QStringLiteral("%1 exited with code %2.").arg(program).arg(result.exitCode)
            : output;
    }
    return QString();
}

void SystemServices::stopProcess(QProcess *&process) {
    if (!process) return;

    auto *current = process;
    process = nullptr;
    current->disconnect();
    if (current->state() != QProcess::NotRunning) {
        current->terminate();
        if (!current->waitForFinished(150)) {
            current->kill();
            current->waitForFinished(300);
        }
    }
    current->deleteLater();
}

void SystemServices::startNotificationMonitor() {
    if (m_shuttingDown || m_notificationMonitor) return;
    const QString executable = findExecutable(QStringLiteral("dbus-monitor"));
    if (executable.isEmpty()) {
        qWarning() << "[SystemServices] dbus-monitor is not available; notification mirroring is disabled";
        return;
    }

    m_notificationMonitor = new QProcess(this);
    m_notificationMonitor->setProcessChannelMode(QProcess::MergedChannels);
    m_notificationMonitor->setProgram(executable);
    m_notificationMonitor->setArguments({
        QStringLiteral("--session"),
        QStringLiteral("type='method_call',interface='org.freedesktop.Notifications',member='Notify'")
    });
    connect(m_notificationMonitor, &QProcess::readyReadStandardOutput, this, &SystemServices::handleNotificationOutput);
    connect(m_notificationMonitor, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
        m_notificationMonitor->deleteLater();
        m_notificationMonitor = nullptr;
        m_notificationBuffer.clear();
        m_notificationCaptureActive = false;
        if (!m_shuttingDown)
            m_notificationRestartTimer.start();
    });
    m_notificationMonitor->start();
}

void SystemServices::startPipeWireMonitor() {
    if (m_shuttingDown || m_pipeWireMonitor) return;
    const QString executable = findExecutable(QStringLiteral("pw-mon"));
    if (executable.isEmpty()) {
        qWarning() << "[SystemServices] pw-mon is not available; PipeWire recording monitoring is disabled";
        return;
    }

    m_pipeWireMonitor = new QProcess(this);
    m_pipeWireMonitor->setProcessChannelMode(QProcess::MergedChannels);
    m_pipeWireMonitor->setProgram(executable);
    m_pipeWireMonitor->setArguments({QStringLiteral("-p"), QStringLiteral("-a")});
    connect(m_pipeWireMonitor, &QProcess::readyReadStandardOutput, this, &SystemServices::handlePipeWireOutput);
    connect(m_pipeWireMonitor, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
        m_pipeWireMonitor->deleteLater();
        m_pipeWireMonitor = nullptr;
        m_pipeWireBuffer.clear();
        if (!m_shuttingDown)
            m_pipeWireRestartTimer.start();
    });
    m_pipeWireMonitor->start();
}

void SystemServices::startRecordingPortalMonitor() {
    if (m_shuttingDown || m_recordingPortalMonitor) return;
    const QString executable = findExecutable(QStringLiteral("dbus-monitor"));
    if (executable.isEmpty()) {
        qWarning() << "[SystemServices] dbus-monitor is not available; portal recording monitoring is disabled";
        return;
    }

    m_recordingPortalMonitor = new QProcess(this);
    m_recordingPortalMonitor->setProcessChannelMode(QProcess::MergedChannels);
    m_recordingPortalMonitor->setProgram(executable);
    m_recordingPortalMonitor->setArguments({
        QStringLiteral("--session"),
        QStringLiteral("type='method_call',interface='org.freedesktop.portal.ScreenCast'"),
        QStringLiteral("type='signal',sender='org.freedesktop.portal.Desktop',interface='org.freedesktop.portal.Session',member='Closed'")
    });
    connect(m_recordingPortalMonitor, &QProcess::readyReadStandardOutput, this, &SystemServices::handleRecordingPortalOutput);
    connect(m_recordingPortalMonitor, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
        m_recordingPortalMonitor->deleteLater();
        m_recordingPortalMonitor = nullptr;
        m_recordingPortalBuffer.clear();
        m_pendingScreenCastMember.clear();
        m_pendingSessionCandidate.clear();
        if (!m_shuttingDown)
            m_recordingPortalRestartTimer.start();
    });
    m_recordingPortalMonitor->start();
}

void SystemServices::processLines(QByteArray &buffer,
                                  const QByteArray &chunk,
                                  const std::function<void(const QString &)> &handler) {
    buffer.append(chunk);
    while (buffer.contains('\n')) {
        const int newlineIndex = buffer.indexOf('\n');
        const QByteArray rawLine = buffer.left(newlineIndex);
        buffer.remove(0, newlineIndex + 1);
        handler(QString::fromUtf8(rawLine).trimmed());
    }

    if (buffer.size() > kMaximumStreamBufferBytes) {
        qWarning() << "[SystemServices] Dropping an oversized unterminated monitor line";
        buffer.clear();
    }
}

void SystemServices::handleNotificationOutput() {
    if (!m_notificationMonitor) return;
    processLines(m_notificationBuffer, m_notificationMonitor->readAllStandardOutput(), [this](const QString &line) {
        handleNotificationLine(line);
    });
}

void SystemServices::handlePipeWireOutput() {
    if (!m_pipeWireMonitor) return;
    processLines(m_pipeWireBuffer, m_pipeWireMonitor->readAllStandardOutput(), [this](const QString &line) {
        handlePipeWireLine(line);
    });
}

void SystemServices::handleRecordingPortalOutput() {
    if (!m_recordingPortalMonitor) return;
    processLines(m_recordingPortalBuffer, m_recordingPortalMonitor->readAllStandardOutput(), [this](const QString &line) {
        handleRecordingPortalLine(line);
    });
}

QString SystemServices::decodeEscapedString(const QString &escaped) const {
    QString decoded;
    decoded.reserve(escaped.size());

    for (int i = 0; i < escaped.size(); ++i) {
        const QChar ch = escaped.at(i);
        if (ch != QLatin1Char('\\') || i + 1 >= escaped.size()) {
            decoded.append(ch);
            continue;
        }

        const QChar next = escaped.at(++i);
        if (next == QLatin1Char('n')) decoded.append(QLatin1Char('\n'));
        else if (next == QLatin1Char('r')) decoded.append(QLatin1Char('\r'));
        else if (next == QLatin1Char('t')) decoded.append(QLatin1Char('\t'));
        else if (next == QLatin1Char('\"')) decoded.append(QLatin1Char('\"'));
        else if (next == QLatin1Char('\\')) decoded.append(QLatin1Char('\\'));
        else decoded.append(next);
    }

    return decoded;
}

bool SystemServices::extractDbusString(const QString &line, QString &result) {
    if (m_pendingNotificationInString) {
        if (line.endsWith(QLatin1Char('\"')) && !line.endsWith(QStringLiteral("\\\""))) {
            m_pendingNotificationStringAccumulator.append(QLatin1Char('\n'));
            m_pendingNotificationStringAccumulator.append(line.left(line.size() - 1));
            result = decodeEscapedString(m_pendingNotificationStringAccumulator);
            m_pendingNotificationInString = false;
            m_pendingNotificationStringAccumulator.clear();
            return true;
        } else {
            m_pendingNotificationStringAccumulator.append(QLatin1Char('\n'));
            m_pendingNotificationStringAccumulator.append(line);
            return false;
        }
    }

    static const QRegularExpression singleLinePattern(QStringLiteral("^\\s*string \"(.*)\"\\s*$"));
    const QRegularExpressionMatch singleMatch = singleLinePattern.match(line);
    if (singleMatch.hasMatch()) {
        result = decodeEscapedString(singleMatch.captured(1));
        return true;
    }

    static const QRegularExpression multiLineStartPattern(QStringLiteral("^\\s*string \"(.*)$"));
    const QRegularExpressionMatch startMatch = multiLineStartPattern.match(line);
    if (startMatch.hasMatch()) {
        m_pendingNotificationInString = true;
        m_pendingNotificationStringAccumulator = startMatch.captured(1);
        return false;
    }

    return false;
}

QString SystemServices::decodeDbusMonitorString(const QString &line) const {
    static const QRegularExpression stringPattern(QStringLiteral("^\\s*string \"(.*)\"\\s*$"));
    const QRegularExpressionMatch match = stringPattern.match(line);
    if (!match.hasMatch()) return QString();
    return decodeEscapedString(match.captured(1));
}

void SystemServices::handleNotificationLine(const QString &line) {
    if (line.isEmpty()) return;

    if (line.contains(QStringLiteral("member=Notify"))) {
        m_notificationCaptureActive = true;
        m_notificationCaptureStage = 0;
        m_pendingNotificationId = ++m_nextNotificationId;
        m_pendingNotificationReplacesId = 0;
        m_pendingNotificationAppName.clear();
        m_pendingNotificationAppIcon.clear();
        m_pendingNotificationSummary.clear();
        m_pendingNotificationBody.clear();
        m_pendingNotificationActions.clear();
        m_pendingNotificationActionKey.clear();
        m_pendingNotificationImagePath.clear();
        m_pendingNotificationUrgency = 1;
        m_pendingNotificationSenderPid = 0;
        m_pendingHintKey.clear();
        m_pendingNotificationInString = false;
        m_pendingNotificationStringAccumulator.clear();

        static const QRegularExpression senderPattern(QStringLiteral("\\bsender=(:[0-9\\.]+)"));
        const QRegularExpressionMatch senderMatch = senderPattern.match(line);
        if (senderMatch.hasMatch()) {
            const QString senderBusName = senderMatch.captured(1);
            QDBusConnectionInterface *iface = QDBusConnection::sessionBus().interface();
            if (iface) {
                QDBusReply<uint> reply = iface->servicePid(senderBusName);
                if (reply.isValid() && reply.value() > 0) {
                    m_pendingNotificationSenderPid = reply.value();
                }
            }
        }
        return;
    }

    if (!m_notificationCaptureActive) return;

    QString parsedString;

    switch (m_notificationCaptureStage) {
    case 0: // app_name
        if (!extractDbusString(line, parsedString)) return;
        m_pendingNotificationAppName = parsedString;
        m_notificationCaptureStage = 1;
        return;
    case 1: // replaces_id (uint32)
        if (line.contains(QStringLiteral("uint32 "))) {
            const QString numStr = line.section(QStringLiteral("uint32 "), 1, 1).trimmed();
            bool ok = false;
            const uint idVal = numStr.toUInt(&ok);
            if (ok && idVal > 0) {
                m_pendingNotificationReplacesId = idVal;
                m_pendingNotificationId = idVal;
            }
            m_notificationCaptureStage = 2;
        }
        return;
    case 2: // app_icon
        if (!extractDbusString(line, parsedString)) return;
        m_pendingNotificationAppIcon = parsedString;
        m_notificationCaptureStage = 3;
        return;
    case 3: // summary
        if (!extractDbusString(line, parsedString)) return;
        m_pendingNotificationSummary = parsedString;
        m_notificationCaptureStage = 4;
        return;
    case 4: // body
        if (!extractDbusString(line, parsedString)) return;
        m_pendingNotificationBody = parsedString;
        m_notificationCaptureStage = 5;
        return;
    case 5: // actions array
        if (line.trimmed() == QStringLiteral("]")) {
            m_notificationCaptureStage = 6;
            return;
        }
        if (extractDbusString(line, parsedString)) {
            if (m_pendingNotificationActionKey.isEmpty()) {
                m_pendingNotificationActionKey = parsedString;
            } else {
                const QString lowerKey = m_pendingNotificationActionKey.toLower();
                const QString lowerText = parsedString.toLower();
                if (lowerKey != QStringLiteral("settings")
                    && lowerKey != QStringLiteral("app-settings")
                    && lowerText != QStringLiteral("settings")
                    && lowerText != QStringLiteral("configure")) {
                    QVariantMap act;
                    act.insert(QStringLiteral("id"), m_pendingNotificationActionKey);
                    act.insert(QStringLiteral("text"), parsedString);
                    m_pendingNotificationActions.append(act);
                }
                m_pendingNotificationActionKey.clear();
            }
        }
        return;
    case 6: // hints dictionary
        if (line.trimmed() == QStringLiteral("]")) {
            if (m_pendingNotificationImagePath.isEmpty()
                && (m_pendingNotificationAppIcon.startsWith(QLatin1Char('/'))
                    || m_pendingNotificationAppIcon.startsWith(QStringLiteral("file://")))) {
                m_pendingNotificationImagePath = m_pendingNotificationAppIcon;
            }

            m_pendingNotificationImagePath = cacheNotificationImage(m_pendingNotificationImagePath, m_pendingNotificationId);
            if (m_pendingNotificationAppIcon.startsWith(QLatin1Char('/'))
                || m_pendingNotificationAppIcon.startsWith(QStringLiteral("file://"))) {
                m_pendingNotificationAppIcon = cacheNotificationImage(m_pendingNotificationAppIcon, m_pendingNotificationId);
            }

            emit notificationReceived(m_pendingNotificationId,
                                      m_pendingNotificationAppName,
                                      m_pendingNotificationAppIcon,
                                      m_pendingNotificationSummary,
                                      m_pendingNotificationBody,
                                      m_pendingNotificationActions,
                                      m_pendingNotificationImagePath,
                                      m_pendingNotificationUrgency,
                                      m_pendingNotificationSenderPid);
            m_notificationCaptureActive = false;
            m_notificationCaptureStage = -1;
            return;
        }
        if (line.contains(QStringLiteral("string \"image-path\""))
            || line.contains(QStringLiteral("string \"image_path\""))
            || line.contains(QStringLiteral("string \"sender-avatar\""))
            || line.contains(QStringLiteral("string \"x-kde-avatar\""))
            || line.contains(QStringLiteral("string \"avatar-path\""))
            || line.contains(QStringLiteral("string \"image-data\""))
            || line.contains(QStringLiteral("string \"icon_data\""))) {
            m_pendingHintKey = QStringLiteral("image-path");
            return;
        }
        if (line.contains(QStringLiteral("string \"sender-pid\""))) {
            m_pendingHintKey = QStringLiteral("sender-pid");
            return;
        }
        if (line.contains(QStringLiteral("string \"urgency\""))) {
            m_pendingHintKey = QStringLiteral("urgency");
            return;
        }
        if (line.contains(QStringLiteral("string \"desktop-entry\""))) {
            m_pendingHintKey = QStringLiteral("desktop-entry");
            return;
        }
        if (!m_pendingHintKey.isEmpty()) {
            if (m_pendingHintKey == QStringLiteral("image-path")) {
                if (line.contains(QStringLiteral("variant")) && line.contains(QStringLiteral("string "))) {
                    static const QRegularExpression variantStringPattern(QStringLiteral("variant\\s+string\\s+\"(.*)\""));
                    const QRegularExpressionMatch m = variantStringPattern.match(line);
                    if (m.hasMatch()) {
                        m_pendingNotificationImagePath = decodeEscapedString(m.captured(1));
                    }
                    m_pendingHintKey.clear();
                }
            } else if (m_pendingHintKey == QStringLiteral("sender-pid")) {
                if (line.contains(QStringLiteral("int64 ")) || line.contains(QStringLiteral("uint32 ")) || line.contains(QStringLiteral("int32 "))) {
                    const QString numStr = line.section(QLatin1Char(' '), -1, -1).trimmed();
                    bool ok = false;
                    const qint64 pidVal = numStr.toLongLong(&ok);
                    if (ok && pidVal > 0) m_pendingNotificationSenderPid = pidVal;
                    m_pendingHintKey.clear();
                }
            } else if (m_pendingHintKey == QStringLiteral("urgency")) {
                if (line.contains(QStringLiteral("byte "))) {
                    const QString bStr = line.section(QStringLiteral("byte "), 1, 1).trimmed();
                    bool ok = false;
                    const int urg = bStr.toInt(&ok);
                    if (ok) m_pendingNotificationUrgency = urg;
                    m_pendingHintKey.clear();
                }
            } else if (m_pendingHintKey == QStringLiteral("desktop-entry")) {
                if (line.contains(QStringLiteral("variant")) && line.contains(QStringLiteral("string "))) {
                    static const QRegularExpression variantStringPattern(QStringLiteral("variant\\s+string\\s+\"(.*)\""));
                    const QRegularExpressionMatch m = variantStringPattern.match(line);
                    if (m.hasMatch() && m_pendingNotificationAppIcon.isEmpty()) {
                        m_pendingNotificationAppIcon = decodeEscapedString(m.captured(1));
                    }
                    m_pendingHintKey.clear();
                }
            }
        }
        return;
    default:
        m_notificationCaptureActive = false;
        m_notificationCaptureStage = -1;
        return;
    }
}

void SystemServices::invokeNotificationAction(uint id, const QString &actionKey) {
    QDBusMessage msg = QDBusMessage::createSignal(
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("ActionInvoked")
    );
    msg << id << actionKey;
    QDBusConnection::sessionBus().send(msg);

    const QString dunstctl = findExecutable(QStringLiteral("dunstctl"));
    if (!dunstctl.isEmpty()) {
        startCommand(dunstctl, {QStringLiteral("action")}, 1000, nullptr);
    }
}

void SystemServices::closeNotification(uint id, uint reason) {
    QDBusMessage msg = QDBusMessage::createSignal(
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("NotificationClosed")
    );
    msg << id << reason;
    QDBusConnection::sessionBus().send(msg);

    const QString dunstctl = findExecutable(QStringLiteral("dunstctl"));
    if (!dunstctl.isEmpty()) {
        startCommand(dunstctl, {QStringLiteral("close"), QString::number(id)}, 1000, nullptr);
    }
}

void SystemServices::copyToClipboard(const QString &text) {
    if (text.isEmpty()) return;

    const QString wlCopy = findExecutable(QStringLiteral("wl-copy"));
    if (!wlCopy.isEmpty()) {
        startCommand(wlCopy, {}, 1000, nullptr, text.toUtf8());
    }

    if (qobject_cast<QGuiApplication *>(QCoreApplication::instance())) {
        if (auto *cb = QGuiApplication::clipboard()) {
            cb->setText(text, QClipboard::Clipboard);
            cb->setText(text, QClipboard::Selection);
        }
    }
}

QString SystemServices::cacheNotificationImage(const QString &sourcePath, uint notifId)
{
    if (sourcePath.isEmpty()) return QString();

    QString localPath = sourcePath;
    if (localPath.startsWith(QLatin1String("file://"))) {
        localPath = QUrl(sourcePath).toLocalFile();
    }
    if (!localPath.startsWith(QLatin1Char('/'))) {
        return sourcePath;
    }

    QFileInfo fi(localPath);
    if (!fi.exists() || !fi.isFile()) {
        return sourcePath;
    }

    // Cache temporary notification files (e.g. from browsers in /tmp or /var/tmp) so they persist in history
    if (localPath.startsWith(QLatin1String("/tmp/"))
        || localPath.startsWith(QLatin1String("/var/tmp/"))
        || localPath.contains(QLatin1String("scoped_dir"))) {
        const QString cacheDir = QDir::homePath() + QStringLiteral("/.cache/tide-island/notification-icons");
        QDir().mkpath(cacheDir);

        const QString ext = fi.suffix().isEmpty() ? QStringLiteral("png") : fi.suffix();
        const QString destPath = QStringLiteral("%1/%2_%3.%4")
            .arg(cacheDir)
            .arg(notifId)
            .arg(QDateTime::currentMSecsSinceEpoch())
            .arg(ext);

        if (QFile::copy(localPath, destPath)) {
            // Keep directory bounded to ~100 files
            QDir cDir(cacheDir);
            QFileInfoList list = cDir.entryInfoList(QDir::Files, QDir::Time);
            while (list.size() > 100) {
                QFile::remove(list.takeLast().absoluteFilePath());
            }
            return destPath;
        }
    }

    return sourcePath;
}

QList<qint64> SystemServices::processAncestorPids(qint64 pid) const {
    QList<qint64> list;
    qint64 curr = pid;
    while (curr > 1 && list.size() < 12) {
        list.append(curr);
        QFile f(QStringLiteral("/proc/%1/status").arg(curr));
        if (!f.open(QIODevice::ReadOnly)) break;
        qint64 ppid = 0;
        while (!f.atEnd()) {
            const QByteArray l = f.readLine();
            if (l.startsWith("PPid:")) {
                ppid = l.mid(5).trimmed().toLongLong();
                break;
            }
        }
        if (ppid <= 1 || ppid == curr) break;
        curr = ppid;
    }
    return list;
}

void SystemServices::focusSenderWindow(const QString &appName, qint64 pid, const QString &summary, const QString &body) {
    // 1. Resolve ancestor PIDs if PID is known (e.g. notify-send -> bash -> kitty)
    QList<qint64> ancestorPids;
    if (pid > 0) {
        ancestorPids = processAncestorPids(pid);
    }

    // 2. Extract agent keywords (antigravity, codex, cursor, claude, opencode, etc.)
    QString agentKeyword;
    const QString combinedText = (appName + QLatin1Char(' ') + summary + QLatin1Char(' ') + body).toLower();
    if (combinedText.contains(QStringLiteral("antigravity")) || combinedText.contains(QStringLiteral("agy"))) {
        agentKeyword = QStringLiteral("agy");
    } else if (combinedText.contains(QStringLiteral("codex"))) {
        agentKeyword = QStringLiteral("codex");
    } else if (combinedText.contains(QStringLiteral("cursor"))) {
        agentKeyword = QStringLiteral("cursor");
    } else if (combinedText.contains(QStringLiteral("claude"))) {
        agentKeyword = QStringLiteral("claude");
    } else if (combinedText.contains(QStringLiteral("opencode"))) {
        agentKeyword = QStringLiteral("opencode");
    } else if (combinedText.contains(QStringLiteral("copilot"))) {
        agentKeyword = QStringLiteral("copilot");
    } else if (combinedText.contains(QStringLiteral("aider"))) {
        agentKeyword = QStringLiteral("aider");
    }

    // Extract significant directory or project words from summary/body
    QStringList extraKeywords;
    static const QRegularExpression wordPattern(QStringLiteral("[a-zA-Z0-9_-]{4,}"));
    QRegularExpressionMatchIterator it = wordPattern.globalMatch(summary + QLatin1Char(' ') + body);
    int kwCount = 0;
    while (it.hasNext() && kwCount < 6) {
        const QString w = it.next().captured(0).toLower();
        if (w != QStringLiteral("needs") && w != QStringLiteral("tool") && w != QStringLiteral("confirmation")
            && w != QStringLiteral("permission") && w != QStringLiteral("request") && w != QStringLiteral("running")) {
            extraKeywords.append(w);
            kwCount++;
        }
    }

    // Check for Niri compositor support
    const QString desktopSession = QString::fromLocal8Bit(qgetenv("XDG_CURRENT_DESKTOP")).toLower();
    const QString tideComp = QString::fromLocal8Bit(qgetenv("TIDE_ISLAND_COMPOSITOR")).toLower();
    bool isNiri = false;
    if (tideComp == QStringLiteral("niri")) {
        isNiri = true;
    } else if (tideComp == QStringLiteral("hyprland")) {
        isNiri = false;
    } else if (desktopSession.contains(QStringLiteral("niri"))) {
        isNiri = true;
    } else if (desktopSession.contains(QStringLiteral("hyprland"))) {
        isNiri = false;
    } else if (!qgetenv("NIRI_SOCKET").isEmpty()) {
        isNiri = true;
    }

    if (isNiri) {
        QString niriSocketPath = QString::fromLocal8Bit(qgetenv("NIRI_SOCKET"));
        if (niriSocketPath.isEmpty()) {
            const QString runDir = QStringLiteral("/run/user/%1").arg(::getuid());
            const QStringList entries = QDir(runDir).entryList({QStringLiteral("niri*.sock")}, QDir::System | QDir::Files);
            if (!entries.isEmpty()) {
                niriSocketPath = runDir + QLatin1Char('/') + entries.first();
            }
        }
        const QString niriCmd = findExecutable(QStringLiteral("niri"));

        QByteArray responseBytes;
        if (!niriSocketPath.isEmpty()) {
            QLocalSocket socket;
            socket.connectToServer(niriSocketPath);
            if (socket.waitForConnected(300)) {
                socket.write("\"Windows\"\n");
                socket.flush();
                while (socket.waitForReadyRead(300)) {
                    responseBytes.append(socket.readAll());
                    if (responseBytes.contains('\n')) break;
                }
            }
        }
        if (responseBytes.isEmpty() && !niriCmd.isEmpty()) {
            QProcess proc;
            proc.start(niriCmd, {QStringLiteral("msg"), QStringLiteral("--json"), QStringLiteral("windows")});
            if (proc.waitForFinished(800)) {
                responseBytes = proc.readAllStandardOutput();
            }
        }

        QJsonArray windowList;
        const QJsonDocument doc = QJsonDocument::fromJson(responseBytes);
        if (doc.isArray()) {
            windowList = doc.array();
        } else if (doc.isObject()) {
            const QJsonObject rootObj = doc.object();
            if (rootObj.contains(QStringLiteral("Ok"))) {
                const QJsonValue okVal = rootObj.value(QStringLiteral("Ok"));
                if (okVal.isArray()) {
                    windowList = okVal.toArray();
                } else if (okVal.isObject()) {
                    const QJsonObject okObj = okVal.toObject();
                    if (okObj.contains(QStringLiteral("Windows"))) {
                        windowList = okObj.value(QStringLiteral("Windows")).toArray();
                    }
                }
            } else if (rootObj.contains(QStringLiteral("Windows"))) {
                windowList = rootObj.value(QStringLiteral("Windows")).toArray();
            }
        }

        quint64 bestId = 0;
        int bestScore = 0;
        QString cleanAppLower = appName.trimmed().toLower();
        if (cleanAppLower == QStringLiteral("notification")) {
            cleanAppLower.clear();
        }

        // Phase 1: Direct PID or ancestor PID match
        for (const QJsonValue &val : windowList) {
            if (!val.isObject()) continue;
            const QJsonObject w = val.toObject();
            const quint64 wid = static_cast<quint64>(w.value(QStringLiteral("id")).toDouble(0));
            const qint64 wpid = static_cast<qint64>(w.value(QStringLiteral("pid")).toDouble(0));

            if (wpid > 0 && (wpid == pid || ancestorPids.contains(wpid))) {
                bestId = wid;
                break;
            }
        }

        // Phase 2: Scoring by app_id, title, agentKeyword, and extra keywords
        if (bestId == 0) {
            for (const QJsonValue &val : windowList) {
                if (!val.isObject()) continue;
                const QJsonObject w = val.toObject();
                const quint64 wid = static_cast<quint64>(w.value(QStringLiteral("id")).toDouble(0));
                const QString wAppId = w.value(QStringLiteral("app_id")).toString().toLower();
                const QString wTitle = w.value(QStringLiteral("title")).toString().toLower();

                bool classMatch = cleanAppLower.isEmpty()
                    || wAppId.contains(cleanAppLower)
                    || cleanAppLower.contains(wAppId)
                    || wTitle.contains(cleanAppLower);

                if (!classMatch && !cleanAppLower.isEmpty()) {
                    static const QRegularExpression splitRegex(QStringLiteral("[\\s\\-_.]+"));
                    const QStringList appWords = cleanAppLower.split(splitRegex, Qt::SkipEmptyParts);
                    for (const QString &aw : appWords) {
                        if (aw.length() >= 3 && (wAppId.contains(aw) || wTitle.contains(aw))) {
                            classMatch = true;
                            break;
                        }
                    }
                }

                if (classMatch) {
                    int score = 1;
                    if (!agentKeyword.isEmpty() && (wTitle.contains(agentKeyword) || wAppId.contains(agentKeyword))) {
                        score += 20;
                    }
                    for (const QString &kw : extraKeywords) {
                        if (!kw.isEmpty() && (wTitle.contains(kw) || wAppId.contains(kw))) {
                            score += 5;
                        }
                    }
                    if (score > bestScore) {
                        bestScore = score;
                        bestId = wid;
                    }
                }
            }
        }

        if (bestId > 0) {
            bool focused = false;
            if (!niriSocketPath.isEmpty()) {
                QLocalSocket socket;
                socket.connectToServer(niriSocketPath);
                if (socket.waitForConnected(300)) {
                    const QString actionJson = QStringLiteral("{\"Action\":{\"FocusWindow\":{\"id\":%1}}}\n").arg(bestId);
                    socket.write(actionJson.toUtf8());
                    socket.flush();
                    socket.waitForBytesWritten(300);
                    if (socket.waitForReadyRead(300)) {
                        focused = true;
                    }
                }
            }
            if (!focused && !niriCmd.isEmpty()) {
                startCommand(niriCmd, {QStringLiteral("msg"), QStringLiteral("action"), QStringLiteral("focus-window"), QStringLiteral("--id"), QString::number(bestId)}, 1000, nullptr);
            }
        }
        return;
    }

    const QString hyprctl = findExecutable(QStringLiteral("hyprctl"));
    if (hyprctl.isEmpty()) return;

    // 3. Format Lua tables
    QString pidsTable;
    for (qint64 p : ancestorPids) {
        pidsTable += QStringLiteral("[%1] = true, ").arg(p);
    }

    QString kwTable;
    for (const QString &kw : extraKeywords) {
        kwTable += QStringLiteral("\"%1\", ").arg(QString(kw).replace(QLatin1Char('"'), QStringLiteral("\\\"")));
    }

    const QString cleanApp = QString(appName).toLower().replace(QLatin1Char('"'), QStringLiteral("\\\""));

    // 4. Construct Lua script for Hyprland: Phase 1 (PID) then Phase 2 (Score/Title)
    const QString script = QStringLiteral(
        "local windows = hl.get_windows()\n"
        "local function activateTarget(targetW)\n"
        "  if not targetW then return false end\n"
        "  local curWs = hl.get_active_workspace()\n"
        "  if targetW.workspace and targetW.workspace.name and targetW.workspace.name:find(\"^special:\") then\n"
        "    hl.dispatch(hl.dsp.workspace.toggle_special(targetW.workspace.name:gsub(\"^special:\", \"\")))\n"
        "  elseif targetW.workspace and curWs and targetW.workspace.id ~= curWs.id then\n"
        "    hl.dispatch(hl.dsp.focus({ workspace = targetW.workspace.id }))\n"
        "  end\n"
        "  hl.dispatch(hl.dsp.focus({ window = targetW }))\n"
        "  local active = hl.get_active_window()\n"
        "  if not active or active.address ~= targetW.address then\n"
        "    for i = 1, 12 do\n"
        "      active = hl.get_active_window()\n"
        "      if not active or active.address == targetW.address then break end\n"
        "      local dir = (targetW.at and active.at and targetW.at[1] < active.at[1]) and \"left\" or \"right\"\n"
        "      hl.dispatch(hl.dsp.focus({ direction = dir }))\n"
        "    end\n"
        "  end\n"
        "  return true\n"
        "end\n"
        "local pids = { %1 }\n"
        "for _, w in ipairs(windows) do\n"
        "  if pids[w.pid] then\n"
        "    activateTarget(w)\n"
        "    return\n"
        "  end\n"
        "end\n"
        "local app = \"%2\"\n"
        "local agentKw = \"%3\"\n"
        "local kws = { %4 }\n"
        "local bestW = nil\n"
        "local bestScore = 0\n"
        "for _, w in ipairs(windows) do\n"
        "  local c = (w.class or \"\"):lower()\n"
        "  local ic = (w.initialClass or \"\"):lower()\n"
        "  local t = (w.title or \"\"):lower()\n"
        "  local it = (w.initialTitle or \"\"):lower()\n"
        "  local classMatch = (app == \"\" or c:find(app, 1, true) or ic:find(app, 1, true))\n"
        "  if classMatch then\n"
        "    local score = 1\n"
        "    if agentKw ~= \"\" and (t:find(agentKw, 1, true) or it:find(agentKw, 1, true)) then\n"
        "      score = score + 20\n"
        "    end\n"
        "    for _, kw in ipairs(kws) do\n"
        "      if kw ~= \"\" and (t:find(kw, 1, true) or it:find(kw, 1, true)) then\n"
        "        score = score + 5\n"
        "      end\n"
        "    end\n"
        "    if score > bestScore then\n"
        "      bestScore = score\n"
        "      bestW = w\n"
        "    end\n"
        "  end\n"
        "end\n"
        "if bestW then\n"
        "  activateTarget(bestW)\n"
        "  return\n"
        "end\n"
    ).arg(pidsTable, cleanApp, agentKeyword, kwTable);

    startCommand(hyprctl, {QStringLiteral("eval"), script}, 1500, nullptr);
}

QString SystemServices::extractHeaderPath(const QString &line) const {
    static const QRegularExpression pathPattern(QStringLiteral("\\bpath=([^;]+);"));
    const QRegularExpressionMatch match = pathPattern.match(line);
    return match.hasMatch() ? match.captured(1) : QString();
}

QString SystemServices::extractObjectPath(const QString &line) const {
    static const QRegularExpression objectPathPattern(QStringLiteral("^object path \"?([^\"\\s]+)\"?"));
    const QRegularExpressionMatch match = objectPathPattern.match(line);
    return match.hasMatch() ? match.captured(1) : QString();
}

bool SystemServices::screenCastMemberHasSessionArgument(const QString &memberName) const {
    return memberName == QLatin1String("SelectSources")
        || memberName == QLatin1String("Start")
        || memberName == QLatin1String("OpenPipeWireRemote");
}

void SystemServices::handleRecordingPortalLine(const QString &line) {
    if (line.isEmpty()) return;

    static const QRegularExpression closedPattern(
        QStringLiteral("^signal\\b.*interface=org\\.freedesktop\\.portal\\.Session; member=Closed"));
    if (closedPattern.match(line).hasMatch()) {
        m_activeScreenCastSessions.remove(extractHeaderPath(line));
        m_pendingScreenCastMember.clear();
        m_pendingSessionCandidate.clear();
        m_recordingSnapshotDebounceTimer.start();
        updateScreenRecordingActive();
        return;
    }

    static const QRegularExpression methodPattern(
        QStringLiteral("^method_call\\b.*interface=org\\.freedesktop\\.portal\\.ScreenCast; member=([A-Za-z0-9_]+)"));
    const QRegularExpressionMatch methodMatch = methodPattern.match(line);
    if (methodMatch.hasMatch()) {
        m_pendingScreenCastMember = methodMatch.captured(1);
        m_pendingSessionCandidate.clear();
        return;
    }

    if (screenCastMemberHasSessionArgument(m_pendingScreenCastMember) && line.startsWith(QStringLiteral("object path "))) {
        const QString sessionPath = extractObjectPath(line);
        if (sessionPath.startsWith(QStringLiteral("/org/freedesktop/portal/desktop/session/"))) {
            m_activeScreenCastSessions.insert(sessionPath);
            m_pendingSessionCandidate = sessionPath;
            if (m_pendingScreenCastMember == QLatin1String("OpenPipeWireRemote")) {
                m_pendingScreenCastMember.clear();
                m_pendingSessionCandidate.clear();
            }
            m_recordingSnapshotDebounceTimer.start();
            updateScreenRecordingActive();
        }
        return;
    }

    if (m_pendingScreenCastMember == QLatin1String("Start") && line.startsWith(QStringLiteral("string "))) {
        m_pendingScreenCastMember.clear();
        m_pendingSessionCandidate.clear();
        return;
    }

    if (m_pendingScreenCastMember == QLatin1String("SelectSources") && line.contains(QStringLiteral("array ["))) {
        m_pendingScreenCastMember.clear();
        m_pendingSessionCandidate.clear();
    }
}

void SystemServices::handlePipeWireLine(const QString &line) {
    if (line.isEmpty()) return;

    const QString lowerLine = line.toLower();
    const bool relevantVideoLine = lowerLine.contains(QStringLiteral("media.class = \"video/source\""))
        || lowerLine.contains(QStringLiteral("media.class = \"stream/input/video\""))
        || lowerLine.contains(QStringLiteral("media.class = \"stream/input/audio\""))
        || lowerLine.contains(QStringLiteral("source-output"))
        || lowerLine.contains(QStringLiteral("xdg-desktop-portal"))
        || lowerLine.contains(QStringLiteral("screencast"))
        || lowerLine.contains(QStringLiteral("screen-cast"))
        || lowerLine.contains(QStringLiteral("screen_cast"))
        || lowerLine.contains(QStringLiteral("xdpw"));
    const bool removalMayAffectActiveCapture = (m_portalPipeWireActive || m_micActive || m_cameraActive)
        && (lowerLine.contains(QStringLiteral("removed:")) || lowerLine.contains(QStringLiteral("destroyed:")));

    if (relevantVideoLine || removalMayAffectActiveCapture)
        m_recordingSnapshotDebounceTimer.start();
}

bool SystemServices::pipeWireBlockLooksLikeScreenCast(const QString &blockText) const {
    if (!blockText.contains(QStringLiteral("media.class = \"Video/Source\"")))
        return false;

    const QString lowerBlock = blockText.toLower();
    if (lowerBlock.contains(QStringLiteral("media.role = \"camera\"")))
        return false;
    if (lowerBlock.contains(QStringLiteral("v4l2")))
        return false;

    return lowerBlock.contains(QStringLiteral("xdg-desktop-portal"))
        || lowerBlock.contains(QStringLiteral("screencast"))
        || lowerBlock.contains(QStringLiteral("screen-cast"))
        || lowerBlock.contains(QStringLiteral("screen_cast"))
        || lowerBlock.contains(QStringLiteral("xdpw"));
}

static bool isPipeWireScreenCastStream(const QString &blockText) {
    const QString lower = blockText.toLower();
    return lower.contains(QStringLiteral("media.role = \"screen\""))
        || lower.contains(QStringLiteral("media.role = \"screencast\""))
        || lower.contains(QStringLiteral("media.role = \"desktop\""))
        || lower.contains(QStringLiteral("media.role = \"window\""))
        || lower.contains(QStringLiteral("media.name = \"xdg-desktop-portal\""))
        || lower.contains(QStringLiteral("portal.screencast"))
        || lower.contains(QStringLiteral("pipewire-screencast"))
        || lower.contains(QStringLiteral("xdpw"));
}

void SystemServices::requestScreenRecordingSnapshot() {
    requestPrivacySnapshot();
}

void SystemServices::requestPrivacySnapshot() {
    if (m_recordingSnapshot) return;

    m_recordingSnapshot = startCommand(
        QStringLiteral("sh"),
        {
            QStringLiteral("-c"),
            QStringLiteral("pactl -f json list source-outputs 2>/dev/null; printf '\\n---TIDE-PRIVACY-SEP---\\n'; fuser /dev/video* 2>/dev/null; printf '\\n---TIDE-PRIVACY-SEP---\\n'; pw-cli ls Node 2>/dev/null; true")
        },
        1500,
        [this](const CommandResult &result) {
            m_recordingSnapshot = nullptr;
            if (result.exitCode == 0 && result.exitStatus == QProcess::NormalExit) {
                handlePrivacySnapshotOutput(QString::fromUtf8(result.stdoutData));
            } else {
                setPortalPipeWireActive(false);
            }
        });
}

void SystemServices::handlePrivacySnapshotOutput(const QString &output) {
    const QString separator = QStringLiteral("---TIDE-PRIVACY-SEP---");
    const QStringList parts = output.split(separator);
    const QString jsonPart = parts.value(0).trimmed();
    QString fuserPart;
    QString pwPart;
    if (parts.size() >= 3) {
        fuserPart = parts.value(1).trimmed();
        pwPart = parts.value(2).trimmed();
    } else if (parts.size() == 2) {
        pwPart = parts.value(1).trimmed();
    }

    // 1. Microphone sources
    bool micActive = false;
    QVariantList micApps;
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPart.toUtf8(), &parseError);
    if (parseError.error == QJsonParseError::NoError && doc.isArray()) {
        const QJsonArray arr = doc.array();
        for (const QJsonValue &val : arr) {
            const QJsonObject obj = val.toObject();
            if (obj.value(QLatin1String("corked")).toBool(false))
                continue;

            const QJsonObject props = obj.value(QLatin1String("properties")).toObject();
            QString appName = props.value(QLatin1String("application.name")).toString().trimmed();
            QString binary = props.value(QLatin1String("application.process.binary")).toString().trimmed();
            if (appName.isEmpty())
                appName = props.value(QLatin1String("node.name")).toString().trimmed();
            if (appName.isEmpty())
                appName = binary;
            if (appName.isEmpty() || appName.compare(QLatin1String("cava"), Qt::CaseInsensitive) == 0
                || binary.compare(QLatin1String("cava"), Qt::CaseInsensitive) == 0)
                continue;

            const QString mediaName = props.value(QLatin1String("media.name")).toString();
            if (mediaName.contains(QLatin1String("monitor"), Qt::CaseInsensitive))
                continue;

            int pid = props.value(QLatin1String("application.process.id")).toString().toInt();

            QVariantMap app;
            app.insert(QStringLiteral("type"), QStringLiteral("mic"));
            app.insert(QStringLiteral("name"), appName);
            app.insert(QStringLiteral("binary"), binary);
            app.insert(QStringLiteral("pid"), pid);
            app.insert(QStringLiteral("icon"), QStringLiteral("audio-input-microphone"));
            app.insert(QStringLiteral("color"), QStringLiteral("#ff9f0a"));
            micApps.append(app);
            micActive = true;
        }
    }

    // 2. Camera streams and screen cast from PipeWire + V4L2 device checks
    bool cameraActive = false;
    bool screencastActive = false;
    QVariantList cameraApps;
    QVariantList screenApps;
    QSet<int> seenCameraPids;
    QSet<int> seenScreenPids;

    if (!pwPart.isEmpty()) {
        const QStringList blocks = pwPart.split(QRegularExpression(QStringLiteral("\\n(?=\\s*id\\s+\\d+,)")));
        for (const QString &block : blocks) {
            if (pipeWireBlockLooksLikeScreenCast(block) || isPipeWireScreenCastStream(block)) {
                screencastActive = true;
            }

            if (block.contains(QStringLiteral("media.class = \"Stream/Input/Video\""))
                || (block.contains(QStringLiteral("media.role = \"Camera\"")) && block.contains(QStringLiteral("Stream/Input")))) {
                static const QRegularExpression appNameRe(QStringLiteral("application\\.name\\s*=\\s*\"([^\"]+)\""));
                static const QRegularExpression binRe(QStringLiteral("application\\.process\\.binary\\s*=\\s*\"([^\"]+)\""));
                static const QRegularExpression pidRe(QStringLiteral("application\\.process\\.id\\s*=\\s*\"([^\"]+)\""));
                static const QRegularExpression nodeRe(QStringLiteral("node\\.name\\s*=\\s*\"([^\"]+)\""));

                QString appName;
                const auto appMatch = appNameRe.match(block);
                if (appMatch.hasMatch()) {
                    appName = appMatch.captured(1);
                } else {
                    const auto nodeMatch = nodeRe.match(block);
                    if (nodeMatch.hasMatch()) appName = nodeMatch.captured(1);
                }

                QString binary;
                const auto binMatch = binRe.match(block);
                if (binMatch.hasMatch()) binary = binMatch.captured(1);

                int pid = 0;
                const auto pidMatch = pidRe.match(block);
                if (pidMatch.hasMatch()) pid = pidMatch.captured(1).toInt();

                if (isPipeWireScreenCastStream(block)) {
                    screencastActive = true;
                    if (pid <= 0 || !seenScreenPids.contains(pid)) {
                        if (pid > 0) seenScreenPids.insert(pid);
                        if (appName.isEmpty()) appName = QStringLiteral("Screen Sharing");

                        QVariantMap app;
                        app.insert(QStringLiteral("type"), QStringLiteral("screen"));
                        app.insert(QStringLiteral("name"), appName);
                        app.insert(QStringLiteral("binary"), binary);
                        app.insert(QStringLiteral("pid"), pid);
                        app.insert(QStringLiteral("icon"), QStringLiteral("video-display"));
                        app.insert(QStringLiteral("color"), QStringLiteral("#ff453a"));
                        screenApps.append(app);
                    }
                } else {
                    cameraActive = true;
                    if (pid > 0) seenCameraPids.insert(pid);
                    if (appName.isEmpty()) appName = QStringLiteral("Camera");

                    QVariantMap app;
                    app.insert(QStringLiteral("type"), QStringLiteral("camera"));
                    app.insert(QStringLiteral("name"), appName);
                    app.insert(QStringLiteral("binary"), binary);
                    app.insert(QStringLiteral("pid"), pid);
                    app.insert(QStringLiteral("icon"), QStringLiteral("camera-web"));
                    app.insert(QStringLiteral("color"), QStringLiteral("#30d158"));
                    cameraApps.append(app);
                }
            }
        }
    }

    // Inspect V4L2 device users from fuser (/dev/video*)
    if (!fuserPart.isEmpty()) {
        const QStringList pidTokens = fuserPart.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
#ifdef Q_OS_UNIX
        const pid_t myPid = getpid();
#else
        const qint64 myPid = 0;
#endif
        for (const QString &tok : pidTokens) {
            bool ok = false;
            const int pid = tok.toInt(&ok);
            if (!ok || pid <= 0 || pid == static_cast<int>(myPid)) continue;
            if (seenCameraPids.contains(pid)) continue;

            QString binary;
            QFile commFile(QStringLiteral("/proc/%1/comm").arg(pid));
            if (commFile.open(QIODevice::ReadOnly)) {
                binary = QString::fromUtf8(commFile.readAll()).trimmed();
            }

            if (binary == QLatin1String("wireplumber") || binary == QLatin1String("pipewire")) {
                continue;
            }

            QString appName;
            if (binary.compare(QLatin1String("chrome"), Qt::CaseInsensitive) == 0) {
                appName = QStringLiteral("Google Chrome");
            } else if (binary.compare(QLatin1String("firefox"), Qt::CaseInsensitive) == 0) {
                appName = QStringLiteral("Firefox");
            } else if (binary.compare(QLatin1String("obs"), Qt::CaseInsensitive) == 0 || binary.compare(QLatin1String("obs-studio"), Qt::CaseInsensitive) == 0) {
                appName = QStringLiteral("OBS Studio");
            } else if (binary.compare(QLatin1String("zoom"), Qt::CaseInsensitive) == 0) {
                appName = QStringLiteral("Zoom");
            } else if (binary.compare(QLatin1String("cheese"), Qt::CaseInsensitive) == 0) {
                appName = QStringLiteral("Cheese");
            } else if (binary.compare(QLatin1String("ffmpeg"), Qt::CaseInsensitive) == 0) {
                appName = QStringLiteral("FFmpeg");
            } else if (binary.compare(QLatin1String("mpv"), Qt::CaseInsensitive) == 0) {
                appName = QStringLiteral("mpv");
            } else if (!binary.isEmpty()) {
                appName = binary;
                appName[0] = appName[0].toUpper();
            } else {
                appName = QStringLiteral("Camera");
                binary = QStringLiteral("camera");
            }

            seenCameraPids.insert(pid);
            cameraActive = true;

            QVariantMap app;
            app.insert(QStringLiteral("type"), QStringLiteral("camera"));
            app.insert(QStringLiteral("name"), appName);
            app.insert(QStringLiteral("binary"), binary);
            app.insert(QStringLiteral("pid"), pid);
            app.insert(QStringLiteral("icon"), QStringLiteral("camera-web"));
            app.insert(QStringLiteral("color"), QStringLiteral("#30d158"));
            cameraApps.append(app);
        }
    }

    // 3. Screen recording
    const bool recorderActive = ScreenRecorderController::instance()
        && ScreenRecorderController::instance()->isRecording();
    if (recorderActive) {
        QVariantMap app;
        app.insert(QStringLiteral("type"), QStringLiteral("screen"));
        app.insert(QStringLiteral("name"), QStringLiteral("Screen Recorder"));
        app.insert(QStringLiteral("binary"), QStringLiteral("wf-recorder"));
        app.insert(QStringLiteral("pid"), 0);
        app.insert(QStringLiteral("icon"), QStringLiteral("video-display"));
        app.insert(QStringLiteral("color"), QStringLiteral("#ff453a"));
        screenApps.prepend(app);
    } else if (screenApps.isEmpty() && (screencastActive || !m_activeScreenCastSessions.isEmpty())) {
        QVariantMap app;
        app.insert(QStringLiteral("type"), QStringLiteral("screen"));
        app.insert(QStringLiteral("name"), QStringLiteral("Screen Sharing / Portal"));
        app.insert(QStringLiteral("binary"), QStringLiteral("xdg-desktop-portal"));
        app.insert(QStringLiteral("pid"), 0);
        app.insert(QStringLiteral("icon"), QStringLiteral("video-display"));
        app.insert(QStringLiteral("color"), QStringLiteral("#ff453a"));
        screenApps.append(app);
    }

    QVariantList allApps = micApps;
    allApps.append(cameraApps);
    allApps.append(screenApps);

    const bool micChanged = (m_micActive != micActive);
    const bool cameraChanged = (m_cameraActive != cameraActive);
    const bool appsChanged = (m_activePrivacyApps != allApps);

    m_micActive = micActive;
    m_cameraActive = cameraActive;
    m_activePrivacyApps = allApps;
    setPortalPipeWireActive(screencastActive);

    const bool captureActive = (m_micActive || m_cameraActive || screencastActive || !m_activeScreenCastSessions.isEmpty());
    const int targetInterval = captureActive ? 10000 : 25000;
    if (m_privacyPollTimer.interval() != targetInterval) {
        m_privacyPollTimer.setInterval(targetInterval);
    }

    if (micChanged || cameraChanged || appsChanged) {
        emit privacyIndicatorsChanged();
    }
}

void SystemServices::applyPipeWireSnapshot(const QString &text) {
    handlePrivacySnapshotOutput(text);
}

void SystemServices::setPortalPipeWireActive(bool active) {
    if (m_portalPipeWireActive == active) return;
    m_portalPipeWireActive = active;
    updateScreenRecordingActive();
}

void SystemServices::updateScreenRecordingActive() {
    const bool recorderActive = ScreenRecorderController::instance()
        && ScreenRecorderController::instance()->isRecording();
    const bool active = !m_activeScreenCastSessions.isEmpty() || m_portalPipeWireActive || recorderActive;
    if (m_screenRecordingActive == active) return;
    m_screenRecordingActive = active;
    emit screenRecordingActiveChanged();
    emit privacyIndicatorsChanged();
}

void SystemServices::requestHyprlandSnapshot(const QString &requestId, const QString &subject) {
    static const QSet<QString> allowedSubjects = {
        QStringLiteral("clients"),
        QStringLiteral("monitors"),
        QStringLiteral("workspaces"),
        QStringLiteral("activeworkspace")
    };

    if (!allowedSubjects.contains(subject)) {
        emit hyprlandSnapshotReady(requestId, subject, QString(), QStringLiteral("Unsupported Hyprland snapshot type."));
        return;
    }

    startCommand(QStringLiteral("hyprctl"), {subject, QStringLiteral("-j")}, 1500,
        [this, requestId, subject](const CommandResult &result) {
            const QString errorText = commandErrorText(QStringLiteral("hyprctl"), result);
            if (!errorText.isEmpty()) {
                emit hyprlandSnapshotReady(requestId, subject, QString(), errorText);
                return;
            }

            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(result.stdoutData, &parseError);
            if (parseError.error != QJsonParseError::NoError) {
                emit hyprlandSnapshotReady(requestId, subject, QString(), parseError.errorString());
                return;
            }

            emit hyprlandSnapshotReady(requestId, subject, QString::fromUtf8(document.toJson(QJsonDocument::Compact)), QString());
        });
}

void SystemServices::ensureUserConfigAvailable() {
    if (m_configAppLaunchRequested)
        return;

    const UserConfigBackend config;
    const QFileInfo configInfo(config.userConfigPath());
    if (configInfo.exists() && config.configError().isEmpty())
        return;

    const QString configAppPath = findExecutable(QStringLiteral("tide-island-config-app"));
    if (configAppPath.isEmpty()) {
        qWarning() << "[SystemServices] Could not find tide-island-config-app for missing or invalid user config:"
                   << config.userConfigPath()
                   << config.configError();
        return;
    }

    m_configAppLaunchRequested = true;
    if (!QProcess::startDetached(configAppPath, {})) {
        m_configAppLaunchRequested = false;
        qWarning() << "[SystemServices] Failed to launch config app:" << configAppPath;
    }
}

void SystemServices::generateWallpaperThumbnail(const QString &sourcePath,
                                                const QString &cachePath,
                                                const QString &cacheDir,
                                                int targetWidth,
                                                int targetHeight,
                                                int quality) {
    const QString requestKey = QStringLiteral("%1\x1f%2\x1f%3x%4\x1f%5")
        .arg(sourcePath, cachePath)
        .arg(targetWidth)
        .arg(targetHeight)
        .arg(quality);
    if (m_wallpaperThumbnailRequests.contains(requestKey))
        return;

    m_wallpaperThumbnailRequests.insert(requestKey);
    auto *watcher = new QFutureWatcher<ThumbnailResult>(this);
    connect(watcher, &QFutureWatcher<ThumbnailResult>::finished, this, [this, watcher, requestKey]() {
        const ThumbnailResult result = watcher->result();
        m_wallpaperThumbnailRequests.remove(requestKey);
        emit wallpaperThumbnailFinished(
            result.sourcePath,
            result.cachePath,
            result.cacheAvailable,
            result.updated,
            result.errorString
        );
        watcher->deleteLater();
    });

    watcher->setFuture(QtConcurrent::run(
        createWallpaperThumbnail,
        sourcePath,
        cachePath,
        cacheDir,
        targetWidth,
        targetHeight,
        quality
    ));
}

double SystemServices::parseBrightnessOutput(const QString &text, bool *ok) const {
    if (ok) *ok = false;
    static const QRegularExpression brightnessPattern(QStringLiteral(",(\\d+)%"));
    const QRegularExpressionMatch match = brightnessPattern.match(text);
    if (!match.hasMatch()) return -1.0;

    bool converted = false;
    const double value = match.captured(1).toDouble(&converted) / 100.0;
    if (ok) *ok = converted;
    return std::clamp(value, 0.0, 1.0);
}

void SystemServices::parseVolumeOutput(const QString &text, double *value, bool *muted, bool *ok) const {
    if (value) *value = -1.0;
    if (muted) *muted = false;
    if (ok) *ok = false;

    static const QRegularExpression volumePattern(QStringLiteral("([0-9]*\\.?[0-9]+)"));
    const QRegularExpressionMatch match = volumePattern.match(text);
    if (!match.hasMatch()) return;

    bool converted = false;
    const double parsedValue = match.captured(1).toDouble(&converted);
    if (!converted) return;

    if (value) *value = std::clamp(parsedValue, 0.0, 1.0);
    if (muted) *muted = text.contains(QStringLiteral("MUTED"), Qt::CaseInsensitive);
    if (ok) *ok = true;
}

void SystemServices::requestBrightness() {
    if (m_brightnessRequestActive) return;
    m_brightnessRequestActive = true;

    startCommand(QStringLiteral("brightnessctl"), {QStringLiteral("-m")}, 1000,
        [this](const CommandResult &result) {
            m_brightnessRequestActive = false;
            const QString errorText = commandErrorText(QStringLiteral("brightnessctl"), result);
            if (!errorText.isEmpty()) {
                emit brightnessSnapshotReady(-1.0, errorText);
                return;
            }

            bool ok = false;
            const double value = parseBrightnessOutput(QString::fromUtf8(result.stdoutData), &ok);
            if (ok && !m_brightnessSettingActive) {
                m_lastAppliedBrightness = value;
            }
            emit brightnessSnapshotReady(value, ok ? QString() : QStringLiteral("Could not parse brightness output."));
        });
}

void SystemServices::setBrightness(double value) {
    m_pendingBrightness = std::clamp(value, 0.0, 1.0);

    if (m_brightnessSettingActive) {
        return;
    }

    if (m_brightnessThrottleTimer.isActive()) {
        return;
    }

    applyPendingBrightness();
}

void SystemServices::applyPendingBrightness() {
    if (m_brightnessSettingActive || m_pendingBrightness < 0.0)
        return;

    const double targetValue = m_pendingBrightness;
    if (m_lastAppliedBrightness >= 0.0 && std::abs(targetValue - m_lastAppliedBrightness) < 0.005) {
        emit brightnessSetFinished(targetValue, true, QString());
        return;
    }

    m_brightnessSettingActive = true;
    startCommand(QStringLiteral("brightnessctl"),
                 {QStringLiteral("set"), QStringLiteral("%1%").arg(qRound(targetValue * 100.0))},
                 1000,
                 [this, targetValue](const CommandResult &result) {
        m_brightnessSettingActive = false;
        m_lastAppliedBrightness = targetValue;
        const QString errorText = commandErrorText(QStringLiteral("brightnessctl"), result);
        emit brightnessSetFinished(targetValue, errorText.isEmpty(), errorText);

        m_brightnessThrottleTimer.start(40);
    });
}

void SystemServices::requestVolume() {
    if (m_volumeRequestActive) return;
    m_volumeRequestActive = true;

    startCommand(QStringLiteral("wpctl"),
                 {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")},
                 1000,
                 [this](const CommandResult &result) {
        m_volumeRequestActive = false;
        const QString errorText = commandErrorText(QStringLiteral("wpctl"), result);
        if (!errorText.isEmpty()) {
            emit volumeSnapshotReady(-1.0, false, errorText);
            return;
        }

        double value = -1.0;
        bool muted = false;
        bool ok = false;
        parseVolumeOutput(QString::fromUtf8(result.stdoutData), &value, &muted, &ok);
        if (ok && !m_volumeSettingActive) {
            m_lastAppliedVolume = value;
        }
        emit volumeSnapshotReady(value, muted, ok ? QString() : QStringLiteral("Could not parse volume output."));
    });
}

void SystemServices::setVolume(double value) {
    m_pendingVolume = std::clamp(value, 0.0, 1.0);

    if (m_volumeSettingActive) {
        return;
    }

    if (m_volumeThrottleTimer.isActive()) {
        return;
    }

    applyPendingVolume();
}

void SystemServices::applyPendingVolume() {
    if (m_volumeSettingActive || m_pendingVolume < 0.0)
        return;

    const double targetValue = m_pendingVolume;
    if (m_lastAppliedVolume >= 0.0 && std::abs(targetValue - m_lastAppliedVolume) < 0.005) {
        emit volumeSetFinished(targetValue, true, QString());
        return;
    }

    m_volumeSettingActive = true;
    startCommand(QStringLiteral("wpctl"),
                 {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QString::number(targetValue, 'f', 2)},
                 1000,
                 [this, targetValue](const CommandResult &result) {
        m_volumeSettingActive = false;
        m_lastAppliedVolume = targetValue;
        const QString errorText = commandErrorText(QStringLiteral("wpctl"), result);
        emit volumeSetFinished(targetValue, errorText.isEmpty(), errorText);

        m_volumeThrottleTimer.start(40);
    });
}

void SystemServices::toggleVolumeMute() {
    startCommand(QStringLiteral("wpctl"),
                 {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("toggle")},
                 1000,
                 [this](const CommandResult &) {
        requestVolume();
    });
}

void SystemServices::requestMicVolume() {
    if (m_micVolumeRequestActive) return;
    m_micVolumeRequestActive = true;

    startCommand(QStringLiteral("wpctl"),
                 {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@")},
                 1000,
                 [this](const CommandResult &result) {
        m_micVolumeRequestActive = false;
        const QString errorText = commandErrorText(QStringLiteral("wpctl"), result);
        if (!errorText.isEmpty()) {
            emit micVolumeSnapshotReady(-1.0, false, errorText);
            return;
        }

        double value = -1.0;
        bool muted = false;
        bool ok = false;
        parseVolumeOutput(QString::fromUtf8(result.stdoutData), &value, &muted, &ok);
        if (ok && !m_micVolumeSettingActive) {
            m_lastAppliedMicVolume = value;
        }
        emit micVolumeSnapshotReady(value, muted, ok ? QString() : QStringLiteral("Could not parse mic volume output."));
    });
}

void SystemServices::setMicVolume(double value) {
    m_pendingMicVolume = std::clamp(value, 0.0, 1.0);

    if (m_micVolumeSettingActive) {
        return;
    }

    if (m_micVolumeThrottleTimer.isActive()) {
        return;
    }

    applyPendingMicVolume();
}

void SystemServices::applyPendingMicVolume() {
    if (m_micVolumeSettingActive || m_pendingMicVolume < 0.0)
        return;

    const double targetValue = m_pendingMicVolume;
    if (m_lastAppliedMicVolume >= 0.0 && std::abs(targetValue - m_lastAppliedMicVolume) < 0.005) {
        emit micVolumeSetFinished(targetValue, true, QString());
        return;
    }

    m_micVolumeSettingActive = true;
    startCommand(QStringLiteral("wpctl"),
                 {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@"), QString::number(targetValue, 'f', 2)},
                 1000,
                 [this, targetValue](const CommandResult &result) {
        m_micVolumeSettingActive = false;
        m_lastAppliedMicVolume = targetValue;
        const QString errorText = commandErrorText(QStringLiteral("wpctl"), result);
        emit micVolumeSetFinished(targetValue, errorText.isEmpty(), errorText);

        m_micVolumeThrottleTimer.start(40);
    });
}

void SystemServices::toggleMicMute() {
    startCommand(QStringLiteral("wpctl"),
                 {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@"), QStringLiteral("toggle")},
                 1000,
                 [this](const CommandResult &) {
        requestMicVolume();
    });
}

void SystemServices::setAudioMonitoringActive(bool active) {
    m_audioMonitoringActive = active;
    if (active) {
        requestAudioOutputs();
        requestAudioInputs();
        requestAppStreams();
    }
}

void SystemServices::refreshAudioIfActive() {
    if (m_audioMonitoringActive) {
        requestAudioOutputs();
        requestAudioInputs();
        requestAppStreams();
    }
    m_recordingSnapshotDebounceTimer.start();
}

void SystemServices::requestAudioOutputs() {
    if (m_audioOutputsRequestActive) return;
    m_audioOutputsRequestActive = true;

    startCommand(QStringLiteral("sh"),
                 {QStringLiteral("-c"), QStringLiteral("pactl get-default-sink 2>/dev/null; echo '---TIDE-SEP---'; pactl -f json list sinks 2>/dev/null")},
                 1000,
                 [this](const CommandResult &result) {
        m_audioOutputsRequestActive = false;
        if (result.exitCode != 0 || result.stdoutData.isEmpty()) return;

        const QString fullText = QString::fromUtf8(result.stdoutData);
        const QStringList parts = fullText.split(QStringLiteral("---TIDE-SEP---"));
        if (parts.size() < 2) return;

        const QString defaultSink = parts[0].trimmed();
        if (m_defaultAudioSink != defaultSink) {
            m_defaultAudioSink = defaultSink;
            emit defaultAudioSinkChanged();
        }

        const QByteArray jsonBytes = parts[1].trimmed().toUtf8();
        QJsonParseError parseErr;
        const QJsonDocument doc = QJsonDocument::fromJson(jsonBytes, &parseErr);
        if (!doc.isArray()) return;

        QVariantList outputs;
        const QJsonArray arr = doc.array();
        for (const QJsonValue &val : arr) {
            if (!val.isObject()) continue;
            const QJsonObject sinkObj = val.toObject();
            const QString sinkName = sinkObj.value(QStringLiteral("name")).toString();
            const QString sinkDesc = sinkObj.value(QStringLiteral("description")).toString();
            const QString activePort = sinkObj.value(QStringLiteral("active_port")).toString();
            const QJsonObject props = sinkObj.value(QStringLiteral("properties")).toObject();
            const QString formFactor = props.value(QStringLiteral("device.form_factor")).toString();
            const QString iconName = props.value(QStringLiteral("device.icon_name")).toString();

            const QJsonArray ports = sinkObj.value(QStringLiteral("ports")).toArray();
            if (ports.size() > 1) {
                for (const QJsonValue &pVal : ports) {
                    if (!pVal.isObject()) continue;
                    const QJsonObject portObj = pVal.toObject();
                    const QString pName = portObj.value(QStringLiteral("name")).toString();
                    const QString pDesc = portObj.value(QStringLiteral("description")).toString();
                    const QString pType = portObj.value(QStringLiteral("type")).toString();
                    const bool isActive = (sinkName == defaultSink && activePort == pName);

                    QString iconType = QStringLiteral("speaker");
                    if (pType.compare(QStringLiteral("headphones"), Qt::CaseInsensitive) == 0 ||
                        pName.contains(QStringLiteral("headphone"), Qt::CaseInsensitive) ||
                        pDesc.contains(QStringLiteral("headphone"), Qt::CaseInsensitive)) {
                        iconType = QStringLiteral("headphones");
                    } else if (pType.compare(QStringLiteral("speaker"), Qt::CaseInsensitive) == 0 ||
                               pName.contains(QStringLiteral("speaker"), Qt::CaseInsensitive)) {
                        iconType = QStringLiteral("speaker");
                    }

                    QVariantMap item;
                    item.insert(QStringLiteral("id"), QStringLiteral("%1:%2").arg(sinkName, pName));
                    item.insert(QStringLiteral("sinkName"), sinkName);
                    item.insert(QStringLiteral("portName"), pName);
                    item.insert(QStringLiteral("name"), pDesc.isEmpty() ? pName : pDesc);
                    item.insert(QStringLiteral("description"), sinkDesc);
                    item.insert(QStringLiteral("iconType"), iconType);
                    item.insert(QStringLiteral("active"), isActive);
                    outputs.append(item);
                }
            } else {
                const bool isActive = (sinkName == defaultSink);
                QString iconType = QStringLiteral("speaker");
                if (sinkName.contains(QStringLiteral("bluez"), Qt::CaseInsensitive) ||
                    sinkDesc.contains(QStringLiteral("Bluetooth"), Qt::CaseInsensitive) ||
                    iconName.contains(QStringLiteral("bluetooth"), Qt::CaseInsensitive)) {
                    iconType = QStringLiteral("bluetooth");
                } else if (sinkDesc.contains(QStringLiteral("hdmi"), Qt::CaseInsensitive) ||
                           sinkDesc.contains(QStringLiteral("displayport"), Qt::CaseInsensitive)) {
                    iconType = QStringLiteral("hdmi");
                } else if (sinkDesc.contains(QStringLiteral("headphone"), Qt::CaseInsensitive) ||
                           formFactor.contains(QStringLiteral("headphone"), Qt::CaseInsensitive)) {
                    iconType = QStringLiteral("headphones");
                }

                QVariantMap item;
                item.insert(QStringLiteral("id"), sinkName);
                item.insert(QStringLiteral("sinkName"), sinkName);
                item.insert(QStringLiteral("portName"), QString());
                item.insert(QStringLiteral("name"), sinkDesc.isEmpty() ? sinkName : sinkDesc);
                item.insert(QStringLiteral("description"), QString());
                item.insert(QStringLiteral("iconType"), iconType);
                item.insert(QStringLiteral("active"), isActive);
                outputs.append(item);
            }
        }

        if (m_audioOutputs != outputs) {
            m_audioOutputs = outputs;
            emit audioOutputsChanged();
        }
    });
}

void SystemServices::requestAudioInputs() {
    if (m_audioInputsRequestActive) return;
    m_audioInputsRequestActive = true;

    startCommand(QStringLiteral("sh"),
                 {QStringLiteral("-c"), QStringLiteral("pactl get-default-source 2>/dev/null; echo '---TIDE-SEP---'; pactl -f json list sources 2>/dev/null")},
                 1000,
                 [this](const CommandResult &result) {
        m_audioInputsRequestActive = false;
        if (result.exitCode != 0 || result.stdoutData.isEmpty()) return;

        const QString fullText = QString::fromUtf8(result.stdoutData);
        const QStringList parts = fullText.split(QStringLiteral("---TIDE-SEP---"));
        if (parts.size() < 2) return;

        const QString defaultSource = parts[0].trimmed();
        if (m_defaultAudioSource != defaultSource) {
            m_defaultAudioSource = defaultSource;
            emit defaultAudioSourceChanged();
        }

        const QByteArray jsonBytes = parts[1].trimmed().toUtf8();
        QJsonParseError parseErr;
        const QJsonDocument doc = QJsonDocument::fromJson(jsonBytes, &parseErr);
        if (!doc.isArray()) return;

        QVariantList inputs;
        const QJsonArray arr = doc.array();
        for (const QJsonValue &val : arr) {
            if (!val.isObject()) continue;
            const QJsonObject srcObj = val.toObject();
            const QString srcName = srcObj.value(QStringLiteral("name")).toString();
            const QJsonObject props = srcObj.value(QStringLiteral("properties")).toObject();

            if (srcName.endsWith(QStringLiteral(".monitor"), Qt::CaseInsensitive) ||
                props.value(QStringLiteral("media.class")).toString() == QLatin1String("Audio/Sink")) {
                continue;
            }

            const QString srcDesc = srcObj.value(QStringLiteral("description")).toString();
            const QString activePort = srcObj.value(QStringLiteral("active_port")).toString();
            const QJsonArray ports = srcObj.value(QStringLiteral("ports")).toArray();

            if (ports.size() > 1) {
                for (const QJsonValue &pVal : ports) {
                    if (!pVal.isObject()) continue;
                    const QJsonObject portObj = pVal.toObject();
                    const QString pName = portObj.value(QStringLiteral("name")).toString();
                    const QString pDesc = portObj.value(QStringLiteral("description")).toString();
                    const bool isActive = (srcName == defaultSource && activePort == pName);

                    QString iconType = QStringLiteral("mic");
                    if (pName.contains(QStringLiteral("headset"), Qt::CaseInsensitive) ||
                        pDesc.contains(QStringLiteral("headset"), Qt::CaseInsensitive)) {
                        iconType = QStringLiteral("headset");
                    }

                    QVariantMap item;
                    item.insert(QStringLiteral("id"), QStringLiteral("%1:%2").arg(srcName, pName));
                    item.insert(QStringLiteral("sourceName"), srcName);
                    item.insert(QStringLiteral("portName"), pName);
                    item.insert(QStringLiteral("name"), pDesc.isEmpty() ? pName : pDesc);
                    item.insert(QStringLiteral("description"), srcDesc);
                    item.insert(QStringLiteral("iconType"), iconType);
                    item.insert(QStringLiteral("active"), isActive);
                    inputs.append(item);
                }
            } else {
                const bool isActive = (srcName == defaultSource);
                QString iconType = QStringLiteral("mic");
                if (srcName.contains(QStringLiteral("bluez"), Qt::CaseInsensitive)) {
                    iconType = QStringLiteral("bluetooth");
                } else if (srcDesc.contains(QStringLiteral("headset"), Qt::CaseInsensitive)) {
                    iconType = QStringLiteral("headset");
                }

                QVariantMap item;
                item.insert(QStringLiteral("id"), srcName);
                item.insert(QStringLiteral("sourceName"), srcName);
                item.insert(QStringLiteral("portName"), QString());
                item.insert(QStringLiteral("name"), srcDesc.isEmpty() ? srcName : srcDesc);
                item.insert(QStringLiteral("description"), QString());
                item.insert(QStringLiteral("iconType"), iconType);
                item.insert(QStringLiteral("active"), isActive);
                inputs.append(item);
            }
        }

        if (m_audioInputs != inputs) {
            m_audioInputs = inputs;
            emit audioInputsChanged();
        }
    });
}

void SystemServices::requestAppStreams() {
    if (m_appStreamsRequestActive) return;
    m_appStreamsRequestActive = true;

    startCommand(QStringLiteral("pactl"),
                 {QStringLiteral("-f"), QStringLiteral("json"), QStringLiteral("list"), QStringLiteral("sink-inputs")},
                 1000,
                 [this](const CommandResult &result) {
        m_appStreamsRequestActive = false;
        if (result.exitCode != 0 || result.stdoutData.isEmpty()) return;

        QJsonParseError parseErr;
        const QJsonDocument doc = QJsonDocument::fromJson(result.stdoutData, &parseErr);
        if (!doc.isArray()) return;

        QVariantList streams;
        const QJsonArray arr = doc.array();
        for (const QJsonValue &val : arr) {
            if (!val.isObject()) continue;
            const QJsonObject streamObj = val.toObject();
            const int index = streamObj.value(QStringLiteral("index")).toInt();
            const bool muted = streamObj.value(QStringLiteral("mute")).toBool();
            const bool corked = streamObj.value(QStringLiteral("corked")).toBool();

            double vol = 1.0;
            const QJsonObject volumeObj = streamObj.value(QStringLiteral("volume")).toObject();
            if (!volumeObj.isEmpty()) {
                const QJsonObject fl = volumeObj.value(QStringLiteral("front-left")).toObject();
                if (!fl.isEmpty()) {
                    vol = static_cast<double>(fl.value(QStringLiteral("value")).toInt()) / 65536.0;
                } else {
                    auto it = volumeObj.begin();
                    if (it != volumeObj.end() && it.value().isObject()) {
                        vol = static_cast<double>(it.value().toObject().value(QStringLiteral("value")).toInt()) / 65536.0;
                    }
                }
            }

            const QJsonObject props = streamObj.value(QStringLiteral("properties")).toObject();
            QString appName = props.value(QStringLiteral("application.name")).toString();
            if (appName.isEmpty()) appName = props.value(QStringLiteral("media.name")).toString();
            if (appName.isEmpty()) appName = props.value(QStringLiteral("node.name")).toString();
            if (appName.isEmpty()) appName = props.value(QStringLiteral("application.process.binary")).toString();
            if (appName.isEmpty()) appName = QStringLiteral("Application");

            QString iconName = props.value(QStringLiteral("application.icon_name")).toString();
            if (iconName.isEmpty()) iconName = props.value(QStringLiteral("application.process.binary")).toString();
            if (iconName.isEmpty()) iconName = appName.toLower();

            const QString mediaTitle = props.value(QStringLiteral("media.name")).toString();

            QVariantMap item;
            item.insert(QStringLiteral("index"), index);
            item.insert(QStringLiteral("name"), appName);
            item.insert(QStringLiteral("title"), mediaTitle);
            item.insert(QStringLiteral("iconName"), iconName);
            item.insert(QStringLiteral("volume"), std::clamp(vol, 0.0, 1.5));
            item.insert(QStringLiteral("muted"), muted);
            item.insert(QStringLiteral("corked"), corked);
            streams.append(item);
        }

        if (m_appStreams != streams) {
            m_appStreams = streams;
            emit appStreamsChanged();
        }
    });
}

void SystemServices::setAudioOutput(const QString &sinkName, const QString &portName) {
    if (sinkName.isEmpty()) return;

    QString cmd = QStringLiteral("pactl set-default-sink '%1'").arg(sinkName);
    if (!portName.isEmpty()) {
        cmd += QStringLiteral(" && pactl set-sink-port '%1' '%2'").arg(sinkName, portName);
    }

    startCommand(QStringLiteral("sh"), {QStringLiteral("-c"), cmd}, 1000, [this](const CommandResult &) {
        requestAudioOutputs();
        requestVolume();
    });
}

void SystemServices::setAudioInput(const QString &sourceName, const QString &portName) {
    if (sourceName.isEmpty()) return;

    QString cmd = QStringLiteral("pactl set-default-source '%1'").arg(sourceName);
    if (!portName.isEmpty()) {
        cmd += QStringLiteral(" && pactl set-source-port '%1' '%2'").arg(sourceName, portName);
    }

    startCommand(QStringLiteral("sh"), {QStringLiteral("-c"), cmd}, 1000, [this](const CommandResult &) {
        requestAudioInputs();
        requestMicVolume();
    });
}

void SystemServices::setAppStreamVolume(int streamIndex, double volume) {
    if (m_shuttingDown) return;

    const int percent = qRound(std::clamp(volume, 0.0, 1.5) * 100.0);
    for (int i = 0; i < m_appStreams.size(); ++i) {
        QVariantMap map = m_appStreams[i].toMap();
        if (map.value(QStringLiteral("index")).toInt() == streamIndex) {
            map.insert(QStringLiteral("volume"), volume);
            m_appStreams[i] = map;
            break;
        }
    }

    m_pendingAppStreamVolumePercents.insert(streamIndex, percent);
    if (m_activeAppStreamVolumeCommands.contains(streamIndex)) {
        return;
    }

    applyPendingAppStreamVolume(streamIndex);
}

void SystemServices::applyPendingAppStreamVolume(int streamIndex) {
    if (m_shuttingDown || !m_pendingAppStreamVolumePercents.contains(streamIndex)) {
        return;
    }

    const int percent = m_pendingAppStreamVolumePercents.take(streamIndex);
    m_activeAppStreamVolumeCommands.insert(streamIndex);

    QPointer<SystemServices> self(this);
    startCommand(QStringLiteral("pactl"),
                 {QStringLiteral("set-sink-input-volume"), QString::number(streamIndex), QStringLiteral("%1%").arg(percent)},
                 800,
                 [self, streamIndex](const CommandResult &) {
        if (!self || self->m_shuttingDown) return;
        self->m_activeAppStreamVolumeCommands.remove(streamIndex);
        if (self->m_pendingAppStreamVolumePercents.contains(streamIndex)) {
            self->applyPendingAppStreamVolume(streamIndex);
        }
    });
}

void SystemServices::toggleAppStreamMute(int streamIndex) {
    for (int i = 0; i < m_appStreams.size(); ++i) {
        QVariantMap map = m_appStreams[i].toMap();
        if (map.value(QStringLiteral("index")).toInt() == streamIndex) {
            const bool current = map.value(QStringLiteral("muted")).toBool();
            map.insert(QStringLiteral("muted"), !current);
            m_appStreams[i] = map;
            emit appStreamsChanged();
            break;
        }
    }

    startCommand(QStringLiteral("pactl"),
                 {QStringLiteral("set-sink-input-mute"), QString::number(streamIndex), QStringLiteral("toggle")},
                 800,
                 [this](const CommandResult &) {
        requestAppStreams();
    });
}

void SystemServices::requestSystemStats() {
    QFile statFile(QStringLiteral("/proc/stat"));
    if (!statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit systemStatsReady(-1.0, -1.0, statFile.errorString());
        return;
    }

    QTextStream statStream(&statFile);
    const QString cpuLine = statStream.readLine();
    statFile.close();

    const QStringList cpuParts = cpuLine.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    if (cpuParts.size() < 6 || cpuParts.first() != QLatin1String("cpu")) {
        emit systemStatsReady(-1.0, -1.0, QStringLiteral("Could not parse CPU stats."));
        return;
    }

    qint64 total = 0;
    for (int index = 1; index < cpuParts.size(); ++index)
        total += cpuParts.at(index).toLongLong();
    const qint64 idle = cpuParts.at(4).toLongLong() + cpuParts.at(5).toLongLong();

    double cpuUsage = 0.0;
    if (m_lastCpuTotal >= 0 && m_lastCpuIdle >= 0 && total > m_lastCpuTotal) {
        const qint64 totalDiff = total - m_lastCpuTotal;
        const qint64 idleDiff = idle - m_lastCpuIdle;
        cpuUsage = totalDiff > 0
            ? std::clamp(double(totalDiff - idleDiff) / double(totalDiff), 0.0, 1.0)
            : 0.0;
    }
    m_lastCpuTotal = total;
    m_lastCpuIdle = idle;

    QFile memFile(QStringLiteral("/proc/meminfo"));
    if (!memFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit systemStatsReady(cpuUsage, -1.0, memFile.errorString());
        return;
    }

    qint64 totalMem = 0;
    qint64 availableMem = 0;
    const QStringList memLines = QString::fromUtf8(memFile.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : memLines) {
        if (line.startsWith(QStringLiteral("MemTotal:"))) {
            const QStringList parts = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
            if (parts.size() >= 2) totalMem = parts.at(1).toLongLong();
        } else if (line.startsWith(QStringLiteral("MemAvailable:"))) {
            const QStringList parts = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
            if (parts.size() >= 2) availableMem = parts.at(1).toLongLong();
        }
    }
    memFile.close();

    const double ramUsage = totalMem > 0
        ? std::clamp(double(totalMem - availableMem) / double(totalMem), 0.0, 1.0)
        : -1.0;
    emit systemStatsReady(cpuUsage, ramUsage, QString());
}

QString SystemServices::parseTlpProfile(const QString &text) const {
    static const QRegularExpression profilePattern(QStringLiteral("TLP profile\\s*=\\s*([a-z-]+)"),
                                                   QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch match = profilePattern.match(text);
    return match.hasMatch() ? match.captured(1).toLower() : QString();
}

QString SystemServices::resolvePowerProfileDriver(const QString &requestedDriver) const {
    const QString driver = requestedDriver.trimmed().toLower();
    if (driver == QLatin1String("disabled") || driver == QLatin1String("none"))
        return QStringLiteral("disabled");
    if (driver == QLatin1String("powerprofilesctl"))
        return QStringLiteral("powerprofilesctl");
    if (driver == QLatin1String("tlp"))
        return QStringLiteral("tlp");

    // Auto-detect
    if (!findExecutable(QStringLiteral("powerprofilesctl")).isEmpty())
        return QStringLiteral("powerprofilesctl");
    if (!findExecutable(QStringLiteral("tlp")).isEmpty())
        return QStringLiteral("tlp");

    return QString();
}

void SystemServices::requestPowerProfileState(const QString &driver) {
    const QString resolved = resolvePowerProfileDriver(driver);
    if (resolved.isEmpty()) {
        emit tlpStateReady(false, QString(), QString(), QStringLiteral("No power profile service found (install power-profiles-daemon or tlp)."));
        return;
    }

    if (resolved == QLatin1String("disabled")) {
        emit tlpStateReady(false, QString(), QString(), QStringLiteral("Power profile controls are disabled."));
        return;
    }

    if (resolved == QLatin1String("powerprofilesctl")) {
        startCommand(QStringLiteral("powerprofilesctl"), {QStringLiteral("get")}, 2000,
            [this](const CommandResult &result) {
                const QString output = trimCommandOutput(result.stdoutData, result.stderrData).trimmed();
                const QString errorText = commandErrorText(QStringLiteral("powerprofilesctl"), result);
                bool ok = errorText.isEmpty() && (result.exitCode == 0) && !output.isEmpty();
                emit tlpStateReady(ok, output.toLower(), output, errorText);
            });
        return;
    }

    if (resolved == QLatin1String("tlp")) {
        if (findExecutable(QStringLiteral("tlp")).isEmpty()) {
            emit tlpStateReady(false, QString(), QString(), QStringLiteral("TLP is not installed."));
            return;
        }

        if (findExecutable(QStringLiteral("tlp-stat")).isEmpty()) {
            emit tlpStateReady(true, QString(), QString(), QString());
            return;
        }

        startCommand(QStringLiteral("tlp-stat"), {QStringLiteral("-s")}, 2000,
            [this](const CommandResult &result) {
                const QString output = trimCommandOutput(result.stdoutData, result.stderrData);
                const QString errorText = commandErrorText(QStringLiteral("tlp-stat"), result);
                emit tlpStateReady(errorText.isEmpty(), parseTlpProfile(output), output, errorText);
            });
        return;
    }
}

void SystemServices::requestTlpState() {
    requestPowerProfileState(QString());
}

void SystemServices::setPowerProfileMode(const QString &driver,
                                        const QString &mode,
                                        const QString &sudoPassword,
                                        bool promptForPassword) {
    static const QSet<QString> allowedModes = {
        QStringLiteral("power-saver"),
        QStringLiteral("balanced"),
        QStringLiteral("performance")
    };

    const QString normalizedMode = mode.trimmed().toLower();
    if (!allowedModes.contains(normalizedMode)) {
        emit tlpSetFinished(false, 125, QString(), QStringLiteral("Unsupported power profile mode."));
        return;
    }

    const QString resolved = resolvePowerProfileDriver(driver);
    if (resolved.isEmpty()) {
        emit tlpSetFinished(false, 127, QString(), QStringLiteral("No power profile service found."));
        return;
    }

    if (resolved == QLatin1String("disabled")) {
        emit tlpSetFinished(false, 125, QString(), QStringLiteral("Power profile controls are disabled."));
        return;
    }

    if (m_tlpSetter) {
        ++m_tlpCommandGeneration;
        m_tlpSetter->kill();
        m_tlpSetter = nullptr;
    }

    if (resolved == QLatin1String("powerprofilesctl")) {
        const int commandGeneration = ++m_tlpCommandGeneration;
        m_tlpSetter = startCommand(
            QStringLiteral("powerprofilesctl"),
            {QStringLiteral("set"), normalizedMode},
            5000,
            [this, commandGeneration, driver](const CommandResult &result) {
                if (commandGeneration != m_tlpCommandGeneration)
                    return;

                m_tlpSetter = nullptr;
                const QString output = trimCommandOutput(result.stdoutData, result.stderrData);
                const QString errorText = commandErrorText(QStringLiteral("powerprofilesctl"), result);
                bool success = errorText.isEmpty() && (result.exitCode == 0);
                emit tlpSetFinished(success, result.exitCode, output, errorText);
                if (success)
                    requestPowerProfileState(driver);
            });
        return;
    }

    if (resolved == QLatin1String("tlp")) {
        if (findExecutable(QStringLiteral("tlp")).isEmpty()) {
            emit tlpSetFinished(false, 127, QString(), QStringLiteral("TLP is not installed."));
            return;
        }

#ifdef Q_OS_UNIX
        if (::getuid() != 0
            && promptForPassword
            && !findExecutable(QStringLiteral("zenity")).isEmpty()
            && !findExecutable(QStringLiteral("sudo")).isEmpty()) {
            const int promptGeneration = ++m_tlpCommandGeneration;
            m_tlpSetter = startCommand(
                QStringLiteral("zenity"),
                {
                    QStringLiteral("--password"),
                    QStringLiteral("--title=Tide Island"),
                    QStringLiteral("--text=Enter your sudo password to change the TLP profile."),
                },
                0,
                [this, normalizedMode, promptGeneration, driver](const CommandResult &result) {
                    if (promptGeneration != m_tlpCommandGeneration)
                        return;

                    m_tlpSetter = nullptr;
                    if (result.exitCode != 0 || result.exitStatus != QProcess::NormalExit) {
                        emit tlpSetFinished(false, result.exitCode, QString(), QStringLiteral("Authentication canceled."));
                        return;
                    }

                    QString password = QString::fromUtf8(result.stdoutData);
                    while (password.endsWith(QLatin1Char('\n')) || password.endsWith(QLatin1Char('\r')))
                        password.chop(1);
                    if (password.isEmpty()) {
                        emit tlpSetFinished(false, 126, QString(), QStringLiteral("A sudo password is required."));
                        return;
                    }

                    setPowerProfileMode(driver, normalizedMode, password, false);
                });
            return;
        }
#endif

        QString program;
        QStringList arguments;
        QByteArray stdinData;

#ifdef Q_OS_UNIX
        if (::getuid() == 0) {
            program = QStringLiteral("tlp");
            arguments = {normalizedMode};
        } else
#endif
        {
            const QString password = sudoPassword.trimmed();
            if (password.isEmpty() && !findExecutable(QStringLiteral("pkexec")).isEmpty()) {
                program = QStringLiteral("pkexec");
                arguments = {QStringLiteral("tlp"), normalizedMode};
            } else if (password.isEmpty()) {
                if (findExecutable(QStringLiteral("sudo")).isEmpty()) {
                    emit tlpSetFinished(false, 126, QString(), QStringLiteral("pkexec or sudo is not installed."));
                    return;
                }
                program = QStringLiteral("sudo");
                arguments = {QStringLiteral("-n"), QStringLiteral("tlp"), normalizedMode};
            } else {
                if (findExecutable(QStringLiteral("sudo")).isEmpty()) {
                    emit tlpSetFinished(false, 126, QString(), QStringLiteral("sudo is not installed."));
                    return;
                }
                program = QStringLiteral("sudo");
                arguments = {QStringLiteral("-S"), QStringLiteral("-p"), QString(), QStringLiteral("tlp"), normalizedMode};
                stdinData = (password + QLatin1Char('\n')).toUtf8();
            }
        }

        const int commandGeneration = ++m_tlpCommandGeneration;
        m_tlpSetter = startCommand(program, arguments, 10000,
            [this, program, commandGeneration, driver](const CommandResult &result) {
                if (commandGeneration != m_tlpCommandGeneration)
                    return;

                m_tlpSetter = nullptr;
                const QString output = trimCommandOutput(result.stdoutData, result.stderrData);
                const QString errorText = commandErrorText(program, result);
                emit tlpSetFinished(errorText.isEmpty(), result.exitCode, output, errorText);
                if (errorText.isEmpty())
                    requestPowerProfileState(driver);
            },
            stdinData);
        return;
    }
}

void SystemServices::setTlpMode(const QString &mode, const QString &sudoPassword, bool promptForPassword) {
    setPowerProfileMode(QString(), mode, sudoPassword, promptForPassword);
}

void SystemServices::cancelTlpApply() {
    if (!m_tlpSetter) return;
    ++m_tlpCommandGeneration;
    m_tlpSetter->kill();
    m_tlpSetter = nullptr;
}

void SystemServices::cancelPowerProfileApply() {
    cancelTlpApply();
}

void SystemServices::detectBatteryThresholdSupport() {
    m_batteryThresholdSupported = false;
    m_batteryThresholdType.clear();
    m_batteryThresholdSysfsPath.clear();
    m_batteryThresholdPresets.clear();

    // 1. Check Lenovo IdeaPad conservation mode
    const QString ideapadPath = QStringLiteral("/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode");
    if (QFile::exists(ideapadPath)) {
        m_batteryThresholdSupported = true;
        m_batteryThresholdType = QStringLiteral("conservation");
        m_batteryThresholdSysfsPath = ideapadPath;
        m_batteryThresholdPresets = QVariantList{80, 100};
        return;
    }

    QDir ideapadDir(QStringLiteral("/sys/bus/platform/drivers/ideapad_acpi"));
    if (ideapadDir.exists()) {
        const QStringList entries = ideapadDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &entry : entries) {
            const QString candidate = ideapadDir.absoluteFilePath(entry + QStringLiteral("/conservation_mode"));
            if (QFile::exists(candidate)) {
                m_batteryThresholdSupported = true;
                m_batteryThresholdType = QStringLiteral("conservation");
                m_batteryThresholdSysfsPath = candidate;
                m_batteryThresholdPresets = QVariantList{80, 100};
                return;
            }
        }
    }

    const QString ideapadPlatform = QStringLiteral("/sys/devices/platform/ideapad_acpi/conservation_mode");
    if (QFile::exists(ideapadPlatform)) {
        m_batteryThresholdSupported = true;
        m_batteryThresholdType = QStringLiteral("conservation");
        m_batteryThresholdSysfsPath = ideapadPlatform;
        m_batteryThresholdPresets = QVariantList{80, 100};
        return;
    }

    // 2. Check standard Linux charge_control_end_threshold (ThinkPad, ASUS, Framework, etc.)
    QDir powerSupplyDir(QStringLiteral("/sys/class/power_supply"));
    if (powerSupplyDir.exists()) {
        const QStringList entries = powerSupplyDir.entryList(QStringList() << QStringLiteral("BAT*"), QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &bat : entries) {
            const QString candidate = powerSupplyDir.absoluteFilePath(bat + QStringLiteral("/charge_control_end_threshold"));
            if (QFile::exists(candidate)) {
                m_batteryThresholdSupported = true;
                m_batteryThresholdType = QStringLiteral("threshold");
                m_batteryThresholdSysfsPath = candidate;
                m_batteryThresholdPresets = QVariantList{80, 85, 90, 100};
                return;
            }
        }
    }

    // 3. Check ASUS specific WMI path
    const QString asusPath = QStringLiteral("/sys/devices/platform/asus-nb-wmi/charge_control_end_threshold");
    if (QFile::exists(asusPath)) {
        m_batteryThresholdSupported = true;
        m_batteryThresholdType = QStringLiteral("threshold");
        m_batteryThresholdSysfsPath = asusPath;
        m_batteryThresholdPresets = QVariantList{80, 85, 90, 100};
        return;
    }
}

void SystemServices::updateBatteryMetrics() {
    QString batDir;
    QDir psDir(QStringLiteral("/sys/class/power_supply"));
    if (psDir.exists()) {
        const QStringList bats = psDir.entryList(QStringList() << QStringLiteral("BAT*"), QDir::Dirs | QDir::NoDotAndDotDot);
        if (!bats.isEmpty()) {
            batDir = psDir.absoluteFilePath(bats.first());
        }
    }

    if (batDir.isEmpty())
        return;

    QFile cycleFile(batDir + QStringLiteral("/cycle_count"));
    if (cycleFile.open(QIODevice::ReadOnly)) {
        m_batteryCycleCount = QString::fromUtf8(cycleFile.readAll()).trimmed().toInt();
        cycleFile.close();
    }

    QFile statusFile(batDir + QStringLiteral("/status"));
    if (statusFile.open(QIODevice::ReadOnly)) {
        m_batteryChargeState = QString::fromUtf8(statusFile.readAll()).trimmed();
        statusFile.close();
    }

    qint64 energyFull = 0;
    qint64 energyFullDesign = 0;

    QFile efFile(batDir + QStringLiteral("/energy_full"));
    if (!efFile.exists())
        efFile.setFileName(batDir + QStringLiteral("/charge_full"));
    if (efFile.open(QIODevice::ReadOnly)) {
        energyFull = QString::fromUtf8(efFile.readAll()).trimmed().toLongLong();
        efFile.close();
    }

    QFile efdFile(batDir + QStringLiteral("/energy_full_design"));
    if (!efdFile.exists())
        efdFile.setFileName(batDir + QStringLiteral("/charge_full_design"));
    if (efdFile.open(QIODevice::ReadOnly)) {
        energyFullDesign = QString::fromUtf8(efdFile.readAll()).trimmed().toLongLong();
        efdFile.close();
    }

    if (energyFullDesign > 0 && energyFull > 0) {
        m_batteryHealthPercent = std::clamp(static_cast<int>(qRound(100.0 * energyFull / energyFullDesign)), 0, 100);
    } else {
        m_batteryHealthPercent = 100;
    }

    emit batteryHealthMetricsChanged();
}

void SystemServices::requestBatteryThresholdState() {
    if (m_batteryThresholdSysfsPath.isEmpty()) {
        detectBatteryThresholdSupport();
    }

    updateBatteryMetrics();

    if (!m_batteryThresholdSupported || m_batteryThresholdSysfsPath.isEmpty()) {
        emit batteryThresholdChanged();
        return;
    }

    QFile file(m_batteryThresholdSysfsPath);
    if (file.open(QIODevice::ReadOnly)) {
        const QString content = QString::fromUtf8(file.readAll()).trimmed();
        file.close();

        if (m_batteryThresholdType == QLatin1String("conservation")) {
            const bool enabled = (content == QLatin1String("1"));
            m_batteryConservationMode = enabled;
            m_batteryThresholdValue = enabled ? 80 : 100;
        } else {
            bool ok = false;
            const int val = content.toInt(&ok);
            if (ok && val > 0) {
                m_batteryThresholdValue = val;
                m_batteryConservationMode = (val <= 80);
            }
        }
        m_batteryThresholdError.clear();
        emit batteryThresholdChanged();
    }
}

void SystemServices::setBatteryConservationMode(bool enabled) {
    if (!m_batteryThresholdSupported || m_batteryThresholdSysfsPath.isEmpty()) {
        emit batteryThresholdFinished(false, QStringLiteral("Battery charge threshold is not supported on this device."));
        return;
    }

    if (m_batteryThresholdType == QLatin1String("conservation")) {
        applyBatteryThresholdValue(enabled ? QStringLiteral("1") : QStringLiteral("0"));
    } else {
        applyBatteryThresholdValue(enabled ? QStringLiteral("80") : QStringLiteral("100"));
    }
}

void SystemServices::setBatteryThreshold(int threshold) {
    if (!m_batteryThresholdSupported || m_batteryThresholdSysfsPath.isEmpty()) {
        emit batteryThresholdFinished(false, QStringLiteral("Battery charge threshold is not supported on this device."));
        return;
    }

    if (m_batteryThresholdType == QLatin1String("conservation")) {
        applyBatteryThresholdValue((threshold <= 80) ? QStringLiteral("1") : QStringLiteral("0"));
    } else {
        applyBatteryThresholdValue(QString::number(std::clamp(threshold, 40, 100)));
    }
}

void SystemServices::applyBatteryThresholdValue(const QString &targetValue) {
    if (m_batteryThresholdSysfsPath.isEmpty())
        return;

    m_batteryThresholdBusy = true;
    m_batteryThresholdError.clear();
    emit batteryThresholdBusyChanged();

    // 1. Direct write (works with 0ms latency when tmpfiles/udev permissions are set)
    QFile file(m_batteryThresholdSysfsPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        const QByteArray bytes = targetValue.toUtf8() + "\n";
        file.write(bytes);
        file.flush();
        file.close();

        m_batteryThresholdBusy = false;
        requestBatteryThresholdState();
        emit batteryThresholdBusyChanged();
        emit batteryThresholdFinished(true, QString());
        return;
    }

    // 2. Fallback to elevated pkexec or sudo
    QString program;
    QStringList arguments;
    QByteArray stdinData;

    const UserConfigBackend config;
    const QString sudoPassword = config.tlpSudoPassword().trimmed();

    if (sudoPassword.isEmpty()) {
        if (!findExecutable(QStringLiteral("pkexec")).isEmpty()) {
            program = QStringLiteral("pkexec");
            arguments = {
                QStringLiteral("sh"),
                QStringLiteral("-c"),
                QStringLiteral("printf '%%s\\n' '%1' > '%2'").arg(targetValue, m_batteryThresholdSysfsPath)
            };
        } else if (!findExecutable(QStringLiteral("sudo")).isEmpty()) {
            program = QStringLiteral("sudo");
            arguments = {
                QStringLiteral("-n"),
                QStringLiteral("sh"),
                QStringLiteral("-c"),
                QStringLiteral("printf '%%s\\n' '%1' > '%2'").arg(targetValue, m_batteryThresholdSysfsPath)
            };
        } else {
            m_batteryThresholdBusy = false;
            m_batteryThresholdError = QStringLiteral("pkexec or sudo is required to set battery threshold.");
            emit batteryThresholdBusyChanged();
            emit batteryThresholdFinished(false, m_batteryThresholdError);
            return;
        }
    } else {
        if (findExecutable(QStringLiteral("sudo")).isEmpty()) {
            m_batteryThresholdBusy = false;
            m_batteryThresholdError = QStringLiteral("sudo is not installed.");
            emit batteryThresholdBusyChanged();
            emit batteryThresholdFinished(false, m_batteryThresholdError);
            return;
        }
        program = QStringLiteral("sudo");
        arguments = {
            QStringLiteral("-S"),
            QStringLiteral("-p"),
            QString(),
            QStringLiteral("sh"),
            QStringLiteral("-c"),
            QStringLiteral("printf '%%s\\n' '%1' > '%2'").arg(targetValue, m_batteryThresholdSysfsPath)
        };
        stdinData = (sudoPassword + QLatin1Char('\n')).toUtf8();
    }

    startCommand(program, arguments, 10000,
        [this, program](const CommandResult &result) {
            m_batteryThresholdBusy = false;
            if (result.exitCode == 0 && result.exitStatus == QProcess::NormalExit) {
                m_batteryThresholdError.clear();
                requestBatteryThresholdState();
                emit batteryThresholdBusyChanged();
                emit batteryThresholdFinished(true, QString());
            } else {
                m_batteryThresholdError = commandErrorText(program, result);
                if (m_batteryThresholdError.isEmpty())
                    m_batteryThresholdError = QStringLiteral("Failed to set battery threshold.");
                emit batteryThresholdBusyChanged();
                emit batteryThresholdFinished(false, m_batteryThresholdError);
            }
        },
        stdinData
    );
}

void SystemServices::setCavaClientActive(const QString &clientId, bool active) {
    const QString normalizedId = clientId.trimmed();
    if (normalizedId.isEmpty()) return;

    if (active)
        m_cavaClients.insert(normalizedId);
    else
        m_cavaClients.remove(normalizedId);

    if (m_cavaClients.isEmpty()) {
        m_cavaRestartTimer.stop();
        stopCava();
        return;
    }

    if (!m_cavaProcess && !m_cavaRestartTimer.isActive())
        startCava();
}

void SystemServices::startCava() {
    if (m_shuttingDown || m_cavaClients.isEmpty() || m_cavaProcess) return;

    const QString executable = findExecutable(QStringLiteral("cava"));
    if (executable.isEmpty()) {
        if (!m_cavaMissingWarned) {
            qWarning() << "[SystemServices] cava is not available; audio visualizer is disabled";
            m_cavaMissingWarned = true;
        }
        return;
    }

    static const QByteArray config =
        "[general]\n"
        "framerate = 30\n"
        "bars = 8\n"
        "autosens = 1\n"
        "[output]\n"
        "method = raw\n"
        "raw_target = /dev/stdout\n"
        "data_format = ascii\n"
        "ascii_max_range = 7\n"
        "channels = mono\n";

    m_cavaProcess = new QProcess(this);
    m_cavaProcess->setProgram(executable);
    m_cavaProcess->setArguments({QStringLiteral("-p"), QStringLiteral("/dev/stdin")});
    m_cavaProcess->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_cavaProcess, &QProcess::started, m_cavaProcess, [this]() {
        if (!m_cavaProcess) return;
        m_cavaProcess->write(config);
        m_cavaProcess->closeWriteChannel();
    });
    connect(m_cavaProcess, &QProcess::readyReadStandardOutput, this, &SystemServices::handleCavaOutput);
    connect(m_cavaProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
        m_cavaProcess->deleteLater();
        m_cavaProcess = nullptr;
        m_cavaBuffer.clear();
        if (!m_shuttingDown && !m_cavaClients.isEmpty())
            m_cavaRestartTimer.start();
    });

    m_cavaProcess->start();
}

void SystemServices::stopCava() {
    stopProcess(m_cavaProcess);
    m_cavaBuffer.clear();
}

void SystemServices::handleCavaOutput() {
    if (!m_cavaProcess) return;
    processLines(m_cavaBuffer, m_cavaProcess->readAllStandardOutput(), [this](const QString &line) {
        handleCavaLine(line);
    });
}

void SystemServices::handleCavaLine(const QString &line) {
    const QStringList parts = line.split(QLatin1Char(';'));
    if (parts.size() < 8) return;

    QVariantList nextLevels;
    nextLevels.reserve(8);
    bool changed = m_cavaLevels.size() != 8;

    for (int index = 0; index < 8; ++index) {
        bool ok = false;
        const double value = std::clamp(parts.at(index).toDouble(&ok) / 7.0, 0.0, 1.0);
        const double nextValue = ok ? value : 0.0;
        if (!changed && std::abs(m_cavaLevels.at(index).toDouble() - nextValue) >= 0.03)
            changed = true;
        nextLevels.append(nextValue);
    }

    if (!changed) return;
    m_cavaLevels = nextLevels;
    emit cavaLevelsChanged();
}

QString SystemServices::defaultTerminalEmulator() const {
    const UserConfigBackend config;
    const QString configured = config.terminalEmulator().trimmed();
    if (!configured.isEmpty())
        return configured;

    const QString envTerm = qEnvironmentVariable("TERMINAL").trimmed();
    if (!envTerm.isEmpty())
        return envTerm;

    static const QStringList candidates = {
        QStringLiteral("xdg-terminal-exec"),
        QStringLiteral("kitty"),
        QStringLiteral("ghostty"),
        QStringLiteral("foot"),
        QStringLiteral("alacritty"),
        QStringLiteral("wezterm"),
        QStringLiteral("konsole"),
        QStringLiteral("gnome-terminal"),
        QStringLiteral("xfce4-terminal"),
        QStringLiteral("xterm")
    };

    for (const QString &candidate : candidates) {
        if (!findExecutable(candidate).isEmpty())
            return candidate;
    }

    return QStringLiteral("xterm");
}

QStringList SystemServices::wrapTerminalCommand(const QStringList &command) const {
    if (command.isEmpty())
        return {};

    const QString terminal = defaultTerminalEmulator();
    const QStringList parts = QProcess::splitCommand(terminal);
    if (parts.isEmpty())
        return QStringList{QStringLiteral("xterm"), QStringLiteral("-e")} + command;

    if (parts.size() > 1) {
        QStringList wrapped = parts;
        wrapped.append(command);
        return wrapped;
    }

    const QString binName = QFileInfo(parts.first()).fileName().toLower();
    if (binName == QLatin1String("wezterm")) {
        return QStringList{parts.first(), QStringLiteral("start"), QStringLiteral("--")} + command;
    }
    if (binName == QLatin1String("gnome-terminal")) {
        return QStringList{parts.first(), QStringLiteral("--")} + command;
    }
    if (binName == QLatin1String("xdg-terminal-exec")) {
        return QStringList{parts.first()} + command;
    }

    return QStringList{parts.first(), QStringLiteral("-e")} + command;
}

