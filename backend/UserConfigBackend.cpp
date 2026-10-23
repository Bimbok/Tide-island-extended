#include "UserConfigBackend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QSet>
#include <QUrl>
#include <QVariant>
#include <Qt>

#include <algorithm>
#include <cmath>

namespace {
QVariantList defaultDynamicIslandLeftSwipeItems()
{
    return {
        QStringLiteral("time"),
        QStringLiteral("date"),
        QStringLiteral("workspace"),
        QStringLiteral("storage"),
        QStringLiteral("battery"),
        QStringLiteral("cpu"),
        QStringLiteral("ram"),
        QStringLiteral("cava"),
        QStringLiteral("albumcover"),
        QStringLiteral("trackname"),
    };
}

QByteArray stripJsonComments(const QByteArray &input)
{
    QString text = QString::fromUtf8(input);

    // Remove /* ... */ block comments
    static const QRegularExpression blockRe(QStringLiteral("/\\*.*?\\*/"), QRegularExpression::DotMatchesEverythingOption);
    text.replace(blockRe, QString());

    // Remove // line comments
    const QStringList lines = text.split(u'\n');
    QStringList stripped;
    bool inString = false;
    for (const QString &line : lines) {
        QString result;
        for (int i = 0; i < line.size(); ++i) {
            const QChar ch = line.at(i);
            if (ch == u'"' && (i == 0 || line.at(i - 1) != u'\\'))
                inString = !inString;
            if (!inString && ch == u'/' && i + 1 < line.size() && line.at(i + 1) == u'/')
                break;
            result.append(ch);
        }
        stripped.append(result);
    }
    return stripped.join(u'\n').toUtf8();
}

QString jsonString(const QJsonObject &object, QLatin1String key, const QString &fallback)
{
    const QJsonValue value = object.value(key);
    return value.isString() && !value.toString().isEmpty() ? value.toString() : fallback;
}

int jsonInt(const QJsonObject &object, QLatin1String key, int fallback)
{
    const QJsonValue value = object.value(key);
    if (!value.isDouble())
        return fallback;

    const double number = value.toDouble();
    return std::isfinite(number) ? qRound(number) : fallback;
}

int jsonBoundedInt(const QJsonObject &object, QLatin1String key, int fallback, int minimum, int maximum)
{
    return std::clamp(jsonInt(object, key, fallback), minimum, maximum);
}

double jsonDouble(const QJsonObject &object, QLatin1String key, double fallback)
{
    const QJsonValue value = object.value(key);
    if (!value.isDouble())
        return fallback;

    const double number = value.toDouble();
    return std::isfinite(number) ? number : fallback;
}

QVariantList jsonArray(const QJsonObject &object, QLatin1String key, const QVariantList &fallback)
{
    const QJsonValue value = object.value(key);
    return value.isArray() ? value.toArray().toVariantList() : fallback;
}

bool jsonBool(const QJsonObject &object, QLatin1String key, bool fallback)
{
    const QJsonValue value = object.value(key);
    return value.isBool() ? value.toBool() : fallback;
}

template<typename Owner, typename T, typename Signal>
void updateField(Owner *owner, T &field, T nextValue, Signal signal)
{
    if (field == nextValue)
        return;

    field = std::move(nextValue);
    emit(owner->*signal)();
}
}

UserConfigBackend::UserConfigBackend(QObject *parent)
    : QObject(parent)
    , m_userConfigPath(configHome() + QStringLiteral("/tide-island/userconfig.json"))
    , m_dynamicIslandLeftSwipeItems(defaultDynamicIslandLeftSwipeItems())
{
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(50);

    connect(&m_reloadTimer, &QTimer::timeout, this, &UserConfigBackend::loadConfig);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &UserConfigBackend::scheduleReload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &UserConfigBackend::scheduleReload);

    loadConfig();
}

QString UserConfigBackend::userConfigPath() const
{
    return m_userConfigPath;
}

QString UserConfigBackend::configError() const
{
    return m_configError;
}

QString UserConfigBackend::defaultWallpaperPath() const
{
    return m_defaultWallpaperPath;
}

QString UserConfigBackend::defaultTlpSudoPassword() const
{
    return m_defaultTlpSudoPassword;
}

QString UserConfigBackend::wallpaperPath() const
{
    if (!m_wallpaperPath.isEmpty() && QFile::exists(m_wallpaperPath))
        return m_wallpaperPath;

    // Check cached wallpaper
    const QString cachePath = QDir::homePath() + QStringLiteral("/.cache/tide-island/last_wallpaper");
    QFile cacheFile(cachePath);
    if (cacheFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString cached = QString::fromUtf8(cacheFile.readLine()).trimmed();
        if (!cached.isEmpty() && QFile::exists(cached))
            return cached;
    }

    // Try detecting from awww query
    const QString awwwBin = QStandardPaths::findExecutable(QStringLiteral("awww"));
    if (!awwwBin.isEmpty()) {
        QProcess proc;
        proc.start(awwwBin, {QStringLiteral("query")});
        if (proc.waitForFinished(300)) {
            const QString output = QString::fromUtf8(proc.readAllStandardOutput());
            const int idx = output.indexOf(QStringLiteral("image: "));
            if (idx != -1) {
                QString path = output.mid(idx + 7).split(u'\n').first().trimmed();
                if (!path.isEmpty() && QFile::exists(path))
                    return path;
            }
        }
    }

    // Try detecting from swww query
    const QString swwwBin = QStandardPaths::findExecutable(QStringLiteral("swww"));
    if (!swwwBin.isEmpty()) {
        QProcess proc;
        proc.start(swwwBin, {QStringLiteral("query")});
        if (proc.waitForFinished(300)) {
            const QString output = QString::fromUtf8(proc.readAllStandardOutput());
            const int idx = output.indexOf(QStringLiteral("image: "));
            if (idx != -1) {
                QString path = output.mid(idx + 7).split(u'\n').first().trimmed();
                if (!path.isEmpty() && QFile::exists(path))
                    return path;
            }
        }
    }

    return m_wallpaperPath;
}

QString UserConfigBackend::wallpaperLibraryPath() const
{
    return m_wallpaperLibraryPath;
}

bool UserConfigBackend::wallpaperPywalEnabled() const
{
    return m_wallpaperPywalEnabled;
}

bool UserConfigBackend::wallpaperCustomCommandEnabled() const
{
    return m_wallpaperCustomCommandEnabled;
}

QString UserConfigBackend::wallpaperCustomCommand() const
{
    return m_wallpaperCustomCommand;
}

QString UserConfigBackend::wallpaperTransitionType() const
{
    return m_wallpaperTransitionType;
}

int UserConfigBackend::wallpaperTransitionStep() const
{
    return m_wallpaperTransitionStep;
}

double UserConfigBackend::wallpaperTransitionDuration() const
{
    return m_wallpaperTransitionDuration;
}

int UserConfigBackend::wallpaperTransitionFps() const
{
    return m_wallpaperTransitionFps;
}

int UserConfigBackend::wallpaperTransitionAngle() const
{
    return m_wallpaperTransitionAngle;
}

QString UserConfigBackend::wallpaperTransitionPosition() const
{
    return m_wallpaperTransitionPosition;
}

QString UserConfigBackend::wallpaperTransitionBezier() const
{
    return m_wallpaperTransitionBezier;
}

QString UserConfigBackend::wallpaperTransitionWave() const
{
    return m_wallpaperTransitionWave;
}

bool UserConfigBackend::wallpaperTransitionInvertY() const
{
    return m_wallpaperTransitionInvertY;
}

QString UserConfigBackend::iconFontFamily() const
{
    return m_iconFontFamily;
}

QString UserConfigBackend::textFontFamily() const
{
    return m_textFontFamily;
}

QString UserConfigBackend::heroFontFamily() const
{
    return m_heroFontFamily;
}

QString UserConfigBackend::timeFontFamily() const
{
    return m_timeFontFamily;
}

QString UserConfigBackend::clockFormat() const
{
    return m_clockFormat;
}

QString UserConfigBackend::tlpSudoPassword() const
{
    return m_tlpSudoPassword;
}

QString UserConfigBackend::tlpPermissionMode() const
{
    return m_tlpPermissionMode;
}

QString UserConfigBackend::powerProfileDriver() const
{
    return m_powerProfileDriver;
}

QString UserConfigBackend::terminalEmulator() const
{
    return m_terminalEmulator;
}

int UserConfigBackend::workspaceOverviewWindowDragButton() const
{
    return m_workspaceOverviewWindowDragButton;
}

int UserConfigBackend::dynamicIslandPrimaryButton() const
{
    return m_dynamicIslandPrimaryButton;
}

QString UserConfigBackend::dynamicIslandPrimaryAction() const
{
    return m_dynamicIslandPrimaryAction;
}

int UserConfigBackend::dynamicIslandSecondaryButton() const
{
    return m_dynamicIslandSecondaryButton;
}

QString UserConfigBackend::dynamicIslandSecondaryAction() const
{
    return m_dynamicIslandSecondaryAction;
}

int UserConfigBackend::dynamicIslandMiddleButton() const
{
    return m_dynamicIslandMiddleButton;
}

QString UserConfigBackend::dynamicIslandMiddleAction() const
{
    return m_dynamicIslandMiddleAction;
}

const QVariantList &UserConfigBackend::dynamicIslandLeftSwipeItems() const
{
    return m_dynamicIslandLeftSwipeItems;
}

bool UserConfigBackend::disableAutoExpandOnTrackChange() const
{
    return m_disableAutoExpandOnTrackChange;
}

int UserConfigBackend::hoverExpandAction() const
{
    return m_hoverExpandAction;
}

bool UserConfigBackend::islandAutoHideEnabled() const
{
    return m_islandAutoHideEnabled;
}

bool UserConfigBackend::islandShowWorkspaceOnAutoHide() const
{
    return m_islandShowWorkspaceOnAutoHide;
}

int UserConfigBackend::islandAutoHideDelayMs() const
{
    return m_islandAutoHideDelayMs;
}

QString UserConfigBackend::islandStyle() const
{
    return m_islandStyle;
}

int UserConfigBackend::islandWidth() const
{
    return m_islandWidth;
}

int UserConfigBackend::islandBackgroundOpacity() const
{
    return m_islandBackgroundOpacity;
}

int UserConfigBackend::islandHeight() const
{
    return m_islandHeight;
}

int UserConfigBackend::islandExclusiveZone() const
{
    return m_islandExclusiveZone;
}

int UserConfigBackend::islandTopMargin() const
{
    return m_islandTopMargin;
}

int UserConfigBackend::islandPositionX() const
{
    return m_islandPositionX;
}

int UserConfigBackend::bodyFontSize() const
{
    return m_bodyFontSize;
}

int UserConfigBackend::titleFontSize() const
{
    return m_titleFontSize;
}

int UserConfigBackend::iconFontSize() const
{
    return m_iconFontSize;
}

bool UserConfigBackend::weatherEnabled() const
{
    return m_weatherEnabled;
}

QString UserConfigBackend::weatherLocation() const
{
    return m_weatherLocation;
}

QString UserConfigBackend::weatherUnits() const
{
    return m_weatherUnits;
}

int UserConfigBackend::weatherRefreshInterval() const
{
    return m_weatherRefreshInterval;
}

bool UserConfigBackend::colorPaletteEnabled() const
{
    return m_colorPaletteEnabled;
}

QString UserConfigBackend::colorsFilePath() const
{
    return m_colorsFilePath;
}

bool UserConfigBackend::dynamicBatteryColorEnabled() const
{
    return m_dynamicBatteryColorEnabled;
}

bool UserConfigBackend::marqueeTrackTitleEnabled() const
{
    return m_marqueeTrackTitleEnabled;
}

bool UserConfigBackend::privacyCameraBubbleEnabled() const
{
    return m_privacyCameraBubbleEnabled;
}

bool UserConfigBackend::privacyMicBubbleEnabled() const
{
    return m_privacyMicBubbleEnabled;
}

QString UserConfigBackend::avatarPath() const
{
    return m_avatarPath;
}

void UserConfigBackend::setAvatarPath(const QString &path)
{
    QString clean = path.trimmed();
    if (clean.startsWith(QLatin1String("file://"))) {
        clean = QUrl(clean).toLocalFile();
    }
    if (clean.startsWith(QLatin1String("~"))) {
        clean.replace(0, 1, QDir::homePath());
    }
    if (m_avatarPath == clean)
        return;

    m_avatarPath = clean;
    emit avatarPathChanged();

    // Persist to userconfig.json
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    obj.insert(QStringLiteral("avatarPath"), clean);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

void UserConfigBackend::setIslandStyle(const QString &style)
{
    QString normalized = style.trimmed().toLower();
    if (normalized != QLatin1String("notch"))
        normalized = QLatin1String("island");

    if (m_islandStyle == normalized)
        return;

    m_islandStyle = normalized;
    emit islandStyleChanged();

    // Persist to userconfig.json
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    obj.insert(QStringLiteral("islandStyle"), normalized);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

bool UserConfigBackend::lockscreenEnabled() const { return m_lockscreenEnabled; }
void UserConfigBackend::setLockscreenEnabled(bool enabled)
{
    if (m_lockscreenEnabled == enabled) return;
    m_lockscreenEnabled = enabled;
    emit lockscreenEnabledChanged();
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    obj.insert(QStringLiteral("lockscreenEnabled"), enabled);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

bool UserConfigBackend::lockscreenMedia() const { return m_lockscreenMedia; }
void UserConfigBackend::setLockscreenMedia(bool enabled)
{
    if (m_lockscreenMedia == enabled) return;
    m_lockscreenMedia = enabled;
    emit lockscreenMediaChanged();
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    obj.insert(QStringLiteral("lockscreenMedia"), enabled);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

bool UserConfigBackend::lockscreenPowerActions() const { return m_lockscreenPowerActions; }
void UserConfigBackend::setLockscreenPowerActions(bool enabled)
{
    if (m_lockscreenPowerActions == enabled) return;
    m_lockscreenPowerActions = enabled;
    emit lockscreenPowerActionsChanged();
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    obj.insert(QStringLiteral("lockscreenPowerActions"), enabled);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

bool UserConfigBackend::lockscreenShowBattery() const { return m_lockscreenShowBattery; }
void UserConfigBackend::setLockscreenShowBattery(bool enabled)
{
    if (m_lockscreenShowBattery == enabled) return;
    m_lockscreenShowBattery = enabled;
    emit lockscreenShowBatteryChanged();
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    obj.insert(QStringLiteral("lockscreenShowBattery"), enabled);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

QString UserConfigBackend::lockscreenPamService() const { return m_lockscreenPamService; }
void UserConfigBackend::setLockscreenPamService(const QString &service)
{
    const QString clean = service.trimmed();
    if (clean.isEmpty() || m_lockscreenPamService == clean) return;
    m_lockscreenPamService = clean;
    emit lockscreenPamServiceChanged();
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    obj.insert(QStringLiteral("lockscreenPamService"), clean);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

QString UserConfigBackend::lockscreenWallpaperPath() const { return m_lockscreenWallpaperPath; }
void UserConfigBackend::setLockscreenWallpaperPath(const QString &path)
{
    const QString clean = path.trimmed();
    if (m_lockscreenWallpaperPath == clean) return;
    m_lockscreenWallpaperPath = clean;
    emit lockscreenWallpaperPathChanged();
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    if (clean.isEmpty())
        obj.remove(QStringLiteral("lockscreenWallpaperPath"));
    else
        obj.insert(QStringLiteral("lockscreenWallpaperPath"), clean);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

bool UserConfigBackend::lockscreenBlur() const { return m_lockscreenBlur; }
void UserConfigBackend::setLockscreenBlur(bool enabled)
{
    if (m_lockscreenBlur == enabled) return;
    m_lockscreenBlur = enabled;
    emit lockscreenBlurChanged();
    QFile file(m_userConfigPath);
    QJsonObject obj;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) obj = doc.object();
        file.close();
    }
    obj.insert(QStringLiteral("lockscreenBlur"), enabled);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

void UserConfigBackend::toggleIslandStyle()
{
    setIslandStyle(m_islandStyle == QLatin1String("notch") ? QStringLiteral("island") : QStringLiteral("notch"));
}

void UserConfigBackend::setDefaultWallpaperPath(const QString &path)
{
    if (m_defaultWallpaperPath == path)
        return;

    m_defaultWallpaperPath = path;
    emit defaultWallpaperPathChanged();
    loadConfig();
}

void UserConfigBackend::setDefaultTlpSudoPassword(const QString &password)
{
    if (m_defaultTlpSudoPassword == password)
        return;

    m_defaultTlpSudoPassword = password;
    emit defaultTlpSudoPasswordChanged();
    loadConfig();
}

int UserConfigBackend::mouseButton(const QVariant &button) const
{
    bool ok = false;
    const int numericButton = button.toInt(&ok);
    if (!ok)
        return Qt::NoButton;

    switch (numericButton) {
    case 1:
        return Qt::LeftButton;
    case 2:
        return Qt::MiddleButton;
    case 3:
        return Qt::RightButton;
    default:
        return numericButton;
    }
}

int UserConfigBackend::mouseButtonsMask(const QVariant &buttons) const
{
    if (!buttons.isValid() || buttons.isNull())
        return Qt::NoButton;

    if (buttons.canConvert<QVariantList>()) {
        int mask = Qt::NoButton;
        const QVariantList buttonList = buttons.toList();
        for (const QVariant &button : buttonList)
            mask |= mouseButton(button);
        return mask;
    }

    return mouseButton(buttons);
}

void UserConfigBackend::reload()
{
    loadConfig();
}

void UserConfigBackend::scheduleReload()
{
    if (!m_reloadTimer.isActive())
        m_reloadTimer.start();
}

void UserConfigBackend::loadConfig()
{
    updateWatchedPaths();

    QJsonObject configObject;
    QString nextConfigError;

    QFile configFile(m_userConfigPath);
    if (configFile.exists()) {
        if (!configFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            nextConfigError = QStringLiteral("Could not read %1: %2").arg(m_userConfigPath, configFile.errorString());
        } else {
            const QByteArray configBytes = configFile.readAll();
            if (!configBytes.trimmed().isEmpty()) {
                const QByteArray strippedBytes = stripJsonComments(configBytes);
                QJsonParseError parseError;
                const QJsonDocument document = QJsonDocument::fromJson(strippedBytes, &parseError);
                if (parseError.error != QJsonParseError::NoError) {
                    nextConfigError = QStringLiteral("Invalid JSON in %1 at offset %2: %3")
                        .arg(m_userConfigPath)
                        .arg(parseError.offset)
                        .arg(parseError.errorString());
                } else if (!document.isObject()) {
                    nextConfigError = QStringLiteral("Invalid JSON in %1: root value must be an object").arg(m_userConfigPath);
                } else {
                    configObject = document.object();
                }
            }
        }
    }

    updateField(this, m_configError, nextConfigError, &UserConfigBackend::configErrorChanged);

    updateField(this, m_wallpaperPath, jsonString(configObject, QLatin1String("wallpaperPath"), m_defaultWallpaperPath), &UserConfigBackend::wallpaperPathChanged);
    updateField(this, m_wallpaperLibraryPath, jsonString(configObject, QLatin1String("wallpaperLibraryPath"), QString()), &UserConfigBackend::wallpaperLibraryPathChanged);
    updateField(this, m_wallpaperPywalEnabled, jsonBool(configObject, QLatin1String("wallpaperPywalEnabled"), false), &UserConfigBackend::wallpaperPywalEnabledChanged);
    updateField(this, m_wallpaperCustomCommandEnabled, jsonBool(configObject, QLatin1String("wallpaperCustomCommandEnabled"), false), &UserConfigBackend::wallpaperCustomCommandEnabledChanged);
    updateField(this, m_wallpaperCustomCommand, jsonString(configObject, QLatin1String("wallpaperCustomCommand"), QString()), &UserConfigBackend::wallpaperCustomCommandChanged);
    updateField(this, m_wallpaperTransitionType, jsonString(configObject, QLatin1String("wallpaperTransitionType"), QStringLiteral("center")), &UserConfigBackend::wallpaperTransitionTypeChanged);
    updateField(this, m_wallpaperTransitionStep, jsonInt(configObject, QLatin1String("wallpaperTransitionStep"), 5), &UserConfigBackend::wallpaperTransitionStepChanged);
    updateField(this, m_wallpaperTransitionDuration, jsonDouble(configObject, QLatin1String("wallpaperTransitionDuration"), 3.0), &UserConfigBackend::wallpaperTransitionDurationChanged);
    updateField(this, m_wallpaperTransitionFps, jsonInt(configObject, QLatin1String("wallpaperTransitionFps"), 60), &UserConfigBackend::wallpaperTransitionFpsChanged);
    updateField(this, m_wallpaperTransitionAngle, jsonInt(configObject, QLatin1String("wallpaperTransitionAngle"), 45), &UserConfigBackend::wallpaperTransitionAngleChanged);
    updateField(this, m_wallpaperTransitionPosition, jsonString(configObject, QLatin1String("wallpaperTransitionPosition"), QStringLiteral("center")), &UserConfigBackend::wallpaperTransitionPositionChanged);
    updateField(this, m_wallpaperTransitionBezier, jsonString(configObject, QLatin1String("wallpaperTransitionBezier"), QStringLiteral(".54,0,.34,.99")), &UserConfigBackend::wallpaperTransitionBezierChanged);
    updateField(this, m_wallpaperTransitionWave, jsonString(configObject, QLatin1String("wallpaperTransitionWave"), QStringLiteral("20,20")), &UserConfigBackend::wallpaperTransitionWaveChanged);
    updateField(this, m_wallpaperTransitionInvertY, jsonBool(configObject, QLatin1String("wallpaperTransitionInvertY"), false), &UserConfigBackend::wallpaperTransitionInvertYChanged);
    updateField(this, m_iconFontFamily, jsonString(configObject, QLatin1String("iconFontFamily"), QStringLiteral("JetBrainsMono Nerd Font")), &UserConfigBackend::iconFontFamilyChanged);
    updateField(this, m_textFontFamily, jsonString(configObject, QLatin1String("textFontFamily"), QStringLiteral("Sans Serif")), &UserConfigBackend::textFontFamilyChanged);
    updateField(this, m_heroFontFamily, jsonString(configObject, QLatin1String("heroFontFamily"), QStringLiteral("Sans Serif")), &UserConfigBackend::heroFontFamilyChanged);
    updateField(this, m_timeFontFamily, jsonString(configObject, QLatin1String("timeFontFamily"), QStringLiteral("Sans Serif")), &UserConfigBackend::timeFontFamilyChanged);
    const QString configuredClockFormat = jsonString(configObject, QLatin1String("clockFormat"), QStringLiteral("12"));
    updateField(this, m_clockFormat, configuredClockFormat == QLatin1String("24") ? QStringLiteral("24") : QStringLiteral("12"), &UserConfigBackend::clockFormatChanged);
    updateField(this, m_tlpSudoPassword, jsonString(configObject, QLatin1String("tlpSudoPassword"), m_defaultTlpSudoPassword), &UserConfigBackend::tlpSudoPasswordChanged);
    updateField(this, m_tlpPermissionMode, jsonString(configObject, QLatin1String("tlpPermissionMode"), QStringLiteral("skip")), &UserConfigBackend::tlpPermissionModeChanged);
    updateField(this, m_powerProfileDriver, jsonString(configObject, QLatin1String("powerProfileDriver"), QStringLiteral("auto")), &UserConfigBackend::powerProfileDriverChanged);
    updateField(this, m_terminalEmulator, jsonString(configObject, QLatin1String("terminalEmulator"), QString()), &UserConfigBackend::terminalEmulatorChanged);
    updateField(this, m_workspaceOverviewWindowDragButton, jsonInt(configObject, QLatin1String("workspaceOverviewWindowDragButton"), 1), &UserConfigBackend::workspaceOverviewWindowDragButtonChanged);
    updateField(this, m_dynamicIslandPrimaryButton, jsonInt(configObject, QLatin1String("dynamicIslandPrimaryButton"), 1), &UserConfigBackend::dynamicIslandPrimaryButtonChanged);
    updateField(this, m_dynamicIslandPrimaryAction, jsonString(configObject, QLatin1String("dynamicIslandPrimaryAction"), QStringLiteral("toggleExpandedPlayer")), &UserConfigBackend::dynamicIslandPrimaryActionChanged);
    updateField(this, m_dynamicIslandSecondaryButton, jsonInt(configObject, QLatin1String("dynamicIslandSecondaryButton"), 3), &UserConfigBackend::dynamicIslandSecondaryButtonChanged);
    updateField(this, m_islandShowWorkspaceOnAutoHide, jsonBool(configObject, QLatin1String("islandShowWorkspaceOnAutoHide"), true), &UserConfigBackend::islandShowWorkspaceOnAutoHideChanged);
    updateField(this, m_dynamicIslandSecondaryAction, jsonString(configObject, QLatin1String("dynamicIslandSecondaryAction"), QStringLiteral("toggleControlCenter")), &UserConfigBackend::dynamicIslandSecondaryActionChanged);
    updateField(this, m_dynamicIslandMiddleButton, jsonInt(configObject, QLatin1String("dynamicIslandMiddleButton"), 2), &UserConfigBackend::dynamicIslandMiddleButtonChanged);
    updateField(this, m_dynamicIslandMiddleAction, jsonString(configObject, QLatin1String("dynamicIslandMiddleAction"), QStringLiteral("toggleClipboard")), &UserConfigBackend::dynamicIslandMiddleActionChanged);
    updateField(this, m_dynamicIslandLeftSwipeItems, jsonArray(configObject, QLatin1String("dynamicIslandLeftSwipeItems"), defaultDynamicIslandLeftSwipeItems()), &UserConfigBackend::dynamicIslandLeftSwipeItemsChanged);
    updateField(this, m_disableAutoExpandOnTrackChange, jsonBool(configObject, QLatin1String("disableAutoExpandOnTrackChange"), false), &UserConfigBackend::disableAutoExpandOnTrackChangeChanged);
    updateField(this, m_hoverExpandAction, jsonInt(configObject, QLatin1String("hoverExpandAction"), 1), &UserConfigBackend::hoverExpandActionChanged);
    updateField(this, m_islandAutoHideEnabled, jsonBool(configObject, QLatin1String("islandAutoHideEnabled"), true), &UserConfigBackend::islandAutoHideEnabledChanged);
    updateField(this, m_islandAutoHideDelayMs, jsonBoundedInt(configObject, QLatin1String("islandAutoHideDelayMs"), 1000, 100, 10000), &UserConfigBackend::islandAutoHideDelayMsChanged);
    QString loadedIslandStyle = jsonString(configObject, QLatin1String("islandStyle"), QStringLiteral("island")).toLower();
    if (loadedIslandStyle != QLatin1String("notch"))
        loadedIslandStyle = QLatin1String("island");
    updateField(this, m_islandStyle, loadedIslandStyle, &UserConfigBackend::islandStyleChanged);
    updateField(this, m_islandWidth, jsonInt(configObject, QLatin1String("islandWidth"), 140), &UserConfigBackend::islandWidthChanged);
    updateField(this, m_islandBackgroundOpacity, jsonBoundedInt(configObject, QLatin1String("islandBackgroundOpacity"), 60, 0, 100), &UserConfigBackend::islandBackgroundOpacityChanged);
    updateField(this, m_islandHeight, jsonInt(configObject, QLatin1String("islandHeight"), 38), &UserConfigBackend::islandHeightChanged);
    updateField(this, m_islandExclusiveZone, jsonBoundedInt(configObject, QLatin1String("islandExclusiveZone"), 45, 0, 1000), &UserConfigBackend::islandExclusiveZoneChanged);
    updateField(this, m_islandTopMargin, jsonBoundedInt(configObject, QLatin1String("islandTopMargin"), 4, 0, 1000), &UserConfigBackend::islandTopMarginChanged);
    updateField(this, m_islandPositionX, jsonInt(configObject, QLatin1String("islandPositionX"), 50), &UserConfigBackend::islandPositionXChanged);
    updateField(this, m_bodyFontSize, jsonInt(configObject, QLatin1String("bodyFontSize"), 16), &UserConfigBackend::bodyFontSizeChanged);
    updateField(this, m_titleFontSize, jsonInt(configObject, QLatin1String("titleFontSize"), 20), &UserConfigBackend::titleFontSizeChanged);
    updateField(this, m_iconFontSize, jsonInt(configObject, QLatin1String("iconFontSize"), 18), &UserConfigBackend::iconFontSizeChanged);
    updateField(this, m_weatherEnabled, jsonBool(configObject, QLatin1String("weatherEnabled"), true), &UserConfigBackend::weatherEnabledChanged);
    updateField(this, m_weatherLocation, jsonString(configObject, QLatin1String("weatherLocation"), QString()), &UserConfigBackend::weatherLocationChanged);
    updateField(this, m_weatherUnits, jsonString(configObject, QLatin1String("weatherUnits"), QStringLiteral("metric")), &UserConfigBackend::weatherUnitsChanged);
    updateField(this, m_weatherRefreshInterval, jsonBoundedInt(configObject, QLatin1String("weatherRefreshInterval"), 1800000, 60000, 86400000), &UserConfigBackend::weatherRefreshIntervalChanged);
    updateField(this, m_colorPaletteEnabled, jsonBool(configObject, QLatin1String("colorPaletteEnabled"), true), &UserConfigBackend::colorPaletteEnabledChanged);
    updateField(this, m_colorsFilePath, jsonString(configObject, QLatin1String("colorsFilePath"), QString()), &UserConfigBackend::colorsFilePathChanged);
    updateField(this, m_dynamicBatteryColorEnabled, jsonBool(configObject, QLatin1String("dynamicBatteryColorEnabled"), true), &UserConfigBackend::dynamicBatteryColorEnabledChanged);
    updateField(this, m_marqueeTrackTitleEnabled, jsonBool(configObject, QLatin1String("marqueeTrackTitleEnabled"), true), &UserConfigBackend::marqueeTrackTitleEnabledChanged);
    updateField(this, m_privacyCameraBubbleEnabled, jsonBool(configObject, QLatin1String("privacyCameraBubbleEnabled"), true), &UserConfigBackend::privacyCameraBubbleEnabledChanged);
    updateField(this, m_privacyMicBubbleEnabled, jsonBool(configObject, QLatin1String("privacyMicBubbleEnabled"), true), &UserConfigBackend::privacyMicBubbleEnabledChanged);

    QString nextAvatarPath = jsonString(configObject, QLatin1String("avatarPath"), jsonString(configObject, QLatin1String("displayPicture"), QString()));
    const QString home = QDir::homePath();
    if (nextAvatarPath.startsWith(QLatin1String("~"))) {
        nextAvatarPath.replace(0, 1, home);
    }
    if (nextAvatarPath.isEmpty()) {
        // Check ChillPill-Shell config for fallback
        QFile cpFile(home + QStringLiteral("/.config/chillpill-shell/config.jsonc"));
        if (cpFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QJsonDocument cpDoc = QJsonDocument::fromJson(stripJsonComments(cpFile.readAll()));
            if (cpDoc.isObject()) {
                const QString cpPic = cpDoc.object().value(QStringLiteral("displayPicture")).toString();
                if (!cpPic.isEmpty()) {
                    QString resolved = cpPic;
                    if (resolved.startsWith(QLatin1String("~"))) {
                        resolved.replace(0, 1, home);
                    }
                    if (QFileInfo::exists(resolved)) {
                        nextAvatarPath = resolved;
                    }
                }
            }
        }
    }
    if (nextAvatarPath.isEmpty()) {
        const QStringList candidates = {
            home + QStringLiteral("/.config/tide-island/avatar.png"),
            home + QStringLiteral("/.config/tide-island/avatar.jpg"),
            home + QStringLiteral("/.pfp.png"),
            home + QStringLiteral("/.pfp.jpg"),
            home + QStringLiteral("/.face"),
            home + QStringLiteral("/.face.icon")
        };
        for (const QString &cand : candidates) {
            if (QFileInfo::exists(cand)) {
                nextAvatarPath = cand;
                break;
            }
        }
    }
    updateField(this, m_avatarPath, nextAvatarPath, &UserConfigBackend::avatarPathChanged);

    updateField(this, m_lockscreenEnabled, jsonBool(configObject, QLatin1String("lockscreenEnabled"), true), &UserConfigBackend::lockscreenEnabledChanged);
    updateField(this, m_lockscreenMedia, jsonBool(configObject, QLatin1String("lockscreenMedia"), true), &UserConfigBackend::lockscreenMediaChanged);
    updateField(this, m_lockscreenPowerActions, jsonBool(configObject, QLatin1String("lockscreenPowerActions"), true), &UserConfigBackend::lockscreenPowerActionsChanged);
    updateField(this, m_lockscreenShowBattery, jsonBool(configObject, QLatin1String("lockscreenShowBattery"), true), &UserConfigBackend::lockscreenShowBatteryChanged);
    updateField(this, m_lockscreenPamService, jsonString(configObject, QLatin1String("lockscreenPamService"), QStringLiteral("login")), &UserConfigBackend::lockscreenPamServiceChanged);
    updateField(this, m_lockscreenWallpaperPath, jsonString(configObject, QLatin1String("lockscreenWallpaperPath"), QString()), &UserConfigBackend::lockscreenWallpaperPathChanged);
    updateField(this, m_lockscreenBlur, jsonBool(configObject, QLatin1String("lockscreenBlur"), true), &UserConfigBackend::lockscreenBlurChanged);

    updateWatchedPaths();
}

void UserConfigBackend::updateWatchedPaths()
{
    const QString configDirectory = QFileInfo(m_userConfigPath).absolutePath();
    const QString configParentDirectory = QFileInfo(configDirectory).absolutePath();
    const QSet<QString> wantedFiles = QFileInfo::exists(m_userConfigPath)
        ? QSet<QString>{m_userConfigPath}
        : QSet<QString>{};
    QSet<QString> wantedDirectories;
    if (QFileInfo::exists(configParentDirectory))
        wantedDirectories.insert(configParentDirectory);
    if (QFileInfo::exists(configDirectory))
        wantedDirectories.insert(configDirectory);

    const QStringList currentFiles = m_watcher.files();
    for (const QString &path : currentFiles) {
        if (!wantedFiles.contains(path))
            m_watcher.removePath(path);
    }

    const QStringList currentDirectories = m_watcher.directories();
    for (const QString &path : currentDirectories) {
        if (!wantedDirectories.contains(path))
            m_watcher.removePath(path);
    }

    for (const QString &path : wantedFiles) {
        if (!m_watcher.files().contains(path))
            m_watcher.addPath(path);
    }

    for (const QString &path : wantedDirectories) {
        if (!m_watcher.directories().contains(path))
            m_watcher.addPath(path);
    }
}

QString UserConfigBackend::configHome() const
{
    const QByteArray xdgConfigHome = qgetenv("XDG_CONFIG_HOME");
    if (!xdgConfigHome.isEmpty())
        return QString::fromLocal8Bit(xdgConfigHome);

    const QByteArray home = qgetenv("HOME");
    return home.isEmpty()
        ? QStringLiteral(".")
        : QString::fromLocal8Bit(home) + QStringLiteral("/.config");
}
