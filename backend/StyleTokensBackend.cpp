#include "StyleTokensBackend.h"
#include "../common/JsonComments.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <Qt>

#include <algorithm>

namespace {
QColor hex(const char *value)
{
    return QColor(QString::fromLatin1(value));
}

QColor parseColor(const QJsonValue &val, const QColor &fallback)
{
    if (!val.isString())
        return fallback;

    QString str = val.toString().trimmed();
    if (str.isEmpty())
        return fallback;

    if (str.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive)) {
        bool ok = false;
        const qulonglong num = str.toULongLong(&ok, 16);
        if (ok) {
            if (str.length() > 8) {
                return QColor::fromRgba(static_cast<QRgb>(num));
            }
            return QColor::fromRgb(static_cast<QRgb>(num));
        }
    }

    if (!str.startsWith(QLatin1Char('#')) && !str.startsWith(QStringLiteral("rgb"), Qt::CaseInsensitive)) {
        str.prepend(QLatin1Char('#'));
    }

    const QColor col(str);
    return col.isValid() ? col : fallback;
}

QColor getColor(const QJsonObject &obj, const QStringList &keys, const QColor &fallback)
{
    for (const QString &k : keys) {
        if (obj.contains(k)) {
            const QColor parsed = parseColor(obj.value(k), QColor());
            if (parsed.isValid())
                return parsed;
        }
    }
    return fallback;
}
}

StyleTokensBackend::StyleTokensBackend(QObject *parent)
    : QObject(parent)
{
    initDefaults();

    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(60);

    connect(&m_reloadTimer, &QTimer::timeout, this, &StyleTokensBackend::loadPalette);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &StyleTokensBackend::scheduleReload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &StyleTokensBackend::scheduleReload);

    loadPalette();
}

void StyleTokensBackend::initDefaults()
{
    m_panel = Qt::black;
    m_surfaceBorder = hex("#26ffffff");
    m_surfaceHighlight = hex("#0cffffff");
    m_module = hex("#1c1c1e");
    m_moduleHover = hex("#232326");
    m_track = hex("#2c2c2e");
    m_cardFill = hex("#26272b");
    m_cardFillActive = hex("#26272b");
    m_cardFillHover = hex("#222327");
    m_connectivityCard = hex("#343437");
    m_connectivityCardHover = hex("#3a3a3d");
    m_prompt = hex("#323236");
    m_input = hex("#212226");
    m_inputBorder = hex("#3f4046");
    m_secondaryButton = hex("#4a4b50");

    m_textPrimary = hex("#f5f5f7");
    m_textPrimaryBright = hex("#f7f8fb");
    m_textSecondary = hex("#8e8e93");
    m_textMuted = hex("#9b9da4");
    m_textSoft = hex("#9da0a8");
    m_textTertiary = hex("#7f828a");
    m_textDisabled = hex("#878a92");
    m_textSubtle = hex("#8f9198");
    m_textDim = hex("#b5b7bf");

    m_accent = hex("#0a84ff");
    m_accentPressed = hex("#0066d6");
    m_accentSoft = hex("#6ea8ff");
    m_textOnAccent = Qt::white;

    m_success = hex("#34c759");
    m_warning = hex("#ffcc00");
    m_danger = hex("#ff3b30");
    m_error = hex("#ff7c72");
    m_disabledControl = hex("#868991");
    m_switchOff = hex("#63656c");

    m_buttonFill = hex("#f5f5f7");
    m_buttonFillHover = Qt::white;
    m_buttonFillPressed = hex("#e9e9ec");

    m_batteryCharging = hex("#34c759");
    m_batteryHigh = hex("#34c759");
    m_batteryMedium = hex("#ffcc00");
    m_batteryLow = hex("#ff9500");
    m_batteryCritical = hex("#ff3b30");

    m_textOnBatteryCharging = Qt::black;
    m_textOnBatteryHigh = Qt::black;
    m_textOnBatteryMedium = Qt::black;
    m_textOnBatteryLow = Qt::black;
    m_textOnBatteryCritical = Qt::white;

    m_overviewCard = hex("#ee17181b");
    m_overviewBorder = hex("#33ffffff");
    m_overviewInnerBorder = hex("#12ffffff");
    m_workspaceCell = hex("#ff202226");
    m_workspaceCellHover = hex("#ff2b2d34");
    m_workspaceCellBorder = hex("#1effffff");
    m_workspaceCellBorderHover = hex("#66d9f6ff");
    m_workspaceOverlay = hex("#42070b10");
    m_workspaceOverlayHover = hex("#280d131a");
    m_workspaceActiveBorder = hex("#73d4ff");
}

QString StyleTokensBackend::resolveConfigHome() const
{
    const QString xdgConfig = QString::fromLocal8Bit(qgetenv("XDG_CONFIG_HOME"));
    if (!xdgConfig.isEmpty())
        return xdgConfig;

    return QDir::homePath() + QStringLiteral("/.config");
}

QString StyleTokensBackend::defaultColorsFilePath() const
{
    return resolveConfigHome() + QStringLiteral("/tide-island/colors.json");
}

QString StyleTokensBackend::effectiveColorsFilePath() const
{
    const QString userConfigPath = resolveConfigHome() + QStringLiteral("/tide-island/userconfig.json");
    QFile file(userConfigPath);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QByteArray data = JsonComments::strip(file.readAll());
        const QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isObject()) {
            const QJsonObject root = doc.object();
            if (root.contains(QStringLiteral("colorsFilePath"))) {
                QString customPath = root.value(QStringLiteral("colorsFilePath")).toString().trimmed();
                if (!customPath.isEmpty()) {
                    if (customPath.startsWith(QLatin1String("~/"))) {
                        customPath = QDir::homePath() + customPath.mid(1);
                    }
                    return customPath;
                }
            }
        }
    }

    return defaultColorsFilePath();
}

void StyleTokensBackend::scheduleReload()
{
    m_reloadTimer.start();
}

void StyleTokensBackend::updateWatchedPaths()
{
    const QStringList currentFiles = m_watcher.files();
    if (!currentFiles.isEmpty())
        m_watcher.removePaths(currentFiles);

    const QStringList currentDirs = m_watcher.directories();
    if (!currentDirs.isEmpty())
        m_watcher.removePaths(currentDirs);

    const QString cfgHome = resolveConfigHome();
    const QString tideDir = cfgHome + QStringLiteral("/tide-island");
    if (QDir(tideDir).exists()) {
        m_watcher.addPath(tideDir);
    }

    const QString userConfigPath = tideDir + QStringLiteral("/userconfig.json");
    if (QFileInfo::exists(userConfigPath)) {
        m_watcher.addPath(userConfigPath);
    }

    const QString colorsPath = m_activeColorsFilePath.isEmpty() ? defaultColorsFilePath() : m_activeColorsFilePath;
    if (QFileInfo::exists(colorsPath)) {
        m_watcher.addPath(colorsPath);
    } else {
        const QString parentDir = QFileInfo(colorsPath).absolutePath();
        if (QDir(parentDir).exists()) {
            m_watcher.addPath(parentDir);
        }
    }
}

void StyleTokensBackend::loadPalette()
{
    const QString cfgHome = resolveConfigHome();
    const QString userConfigPath = cfgHome + QStringLiteral("/tide-island/userconfig.json");

    bool paletteEnabledByUser = true;
    QFile userConfigFile(userConfigPath);
    if (userConfigFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QByteArray data = JsonComments::strip(userConfigFile.readAll());
        const QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isObject()) {
            const QJsonObject root = doc.object();
            if (root.contains(QStringLiteral("colorPaletteEnabled"))) {
                paletteEnabledByUser = root.value(QStringLiteral("colorPaletteEnabled")).toBool(true);
            }
        }
    }

    m_activeColorsFilePath = effectiveColorsFilePath();
    updateWatchedPaths();

    if (!paletteEnabledByUser) {
        if (m_paletteLoaded) {
            initDefaults();
            m_paletteLoaded = false;
            emit colorsChanged();
        }
        return;
    }

    QFile colorsFile(m_activeColorsFilePath);
    if (!colorsFile.exists() || !colorsFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (m_paletteLoaded) {
            initDefaults();
            m_paletteLoaded = false;
            emit colorsChanged();
        }
        return;
    }

    const QByteArray rawData = JsonComments::strip(colorsFile.readAll());
    const QJsonDocument doc = QJsonDocument::fromJson(rawData);
    if (!doc.isObject()) {
        return;
    }

    const QJsonObject rootObj = doc.object();
    QJsonObject paletteObj = rootObj;

    // Check if colors are nested under "colors" or "defs"
    if (rootObj.contains(QStringLiteral("colors")) && rootObj.value(QStringLiteral("colors")).isObject()) {
        const QJsonObject nested = rootObj.value(QStringLiteral("colors")).toObject();
        for (auto it = nested.begin(); it != nested.end(); ++it) {
            if (!paletteObj.contains(it.key()))
                paletteObj.insert(it.key(), it.value());
        }
    }
    if (rootObj.contains(QStringLiteral("defs")) && rootObj.value(QStringLiteral("defs")).isObject()) {
        const QJsonObject nested = rootObj.value(QStringLiteral("defs")).toObject();
        for (auto it = nested.begin(); it != nested.end(); ++it) {
            if (!paletteObj.contains(it.key()))
                paletteObj.insert(it.key(), it.value());
        }
    }

    // Default colors for fallback
    initDefaults();

    // 1. Panel & Backgrounds
    m_panel = getColor(paletteObj,
        {QStringLiteral("panel"), QStringLiteral("background"), QStringLiteral("surface_container_lowest"), QStringLiteral("surface")},
        m_panel);

    m_surfaceBorder = getColor(paletteObj,
        {QStringLiteral("surfaceBorder"), QStringLiteral("border")},
        m_surfaceBorder);

    m_surfaceHighlight = getColor(paletteObj,
        {QStringLiteral("surfaceHighlight"), QStringLiteral("highlight")},
        m_surfaceHighlight);

    // 2. Module / Card surfaces
    m_module = getColor(paletteObj,
        {QStringLiteral("module"), QStringLiteral("surface_container_low"), QStringLiteral("surface_container"), QStringLiteral("surface")},
        m_module);

    m_moduleHover = getColor(paletteObj,
        {QStringLiteral("moduleHover"), QStringLiteral("surface_container"), QStringLiteral("surface_container_high")},
        m_moduleHover);

    m_track = getColor(paletteObj,
        {QStringLiteral("track"), QStringLiteral("surface_variant"), QStringLiteral("surface_container_high")},
        m_track);

    m_cardFill = getColor(paletteObj,
        {QStringLiteral("cardFill"), QStringLiteral("surface_container"), QStringLiteral("surface_variant")},
        m_cardFill);

    m_cardFillActive = getColor(paletteObj,
        {QStringLiteral("cardFillActive"), QStringLiteral("surface_container"), QStringLiteral("surface_variant")},
        m_cardFillActive);

    m_cardFillHover = getColor(paletteObj,
        {QStringLiteral("cardFillHover"), QStringLiteral("surface_container_high"), QStringLiteral("surface_container_highest")},
        m_cardFillHover);

    m_connectivityCard = getColor(paletteObj,
        {QStringLiteral("connectivityCard"), QStringLiteral("surface_container_high"), QStringLiteral("surface_container")},
        m_connectivityCard);

    m_connectivityCardHover = getColor(paletteObj,
        {QStringLiteral("connectivityCardHover"), QStringLiteral("surface_container_highest"), QStringLiteral("surface_container_high")},
        m_connectivityCardHover);

    m_prompt = getColor(paletteObj,
        {QStringLiteral("prompt"), QStringLiteral("surface_container_lowest"), QStringLiteral("surface_container_low")},
        m_prompt);

    m_input = getColor(paletteObj,
        {QStringLiteral("input"), QStringLiteral("surface_container_lowest"), QStringLiteral("surface_container_low")},
        m_input);

    m_inputBorder = getColor(paletteObj,
        {QStringLiteral("inputBorder"), QStringLiteral("outline_variant"), QStringLiteral("outline")},
        m_inputBorder);

    m_secondaryButton = getColor(paletteObj,
        {QStringLiteral("secondaryButton"), QStringLiteral("surface_container_high"), QStringLiteral("secondary_container")},
        m_secondaryButton);

    // 3. Text & Content
    m_textPrimary = getColor(paletteObj,
        {QStringLiteral("textPrimary"), QStringLiteral("on_surface"), QStringLiteral("on_background")},
        m_textPrimary);

    m_textPrimaryBright = getColor(paletteObj,
        {QStringLiteral("textPrimaryBright"), QStringLiteral("on_surface"), QStringLiteral("on_background")},
        m_textPrimaryBright);

    m_textSecondary = getColor(paletteObj,
        {QStringLiteral("textSecondary"), QStringLiteral("on_surface_variant")},
        m_textSecondary);

    m_textMuted = getColor(paletteObj,
        {QStringLiteral("textMuted"), QStringLiteral("outline")},
        m_textMuted);

    m_textSoft = getColor(paletteObj,
        {QStringLiteral("textSoft"), QStringLiteral("on_surface_variant"), QStringLiteral("outline")},
        m_textSoft);

    m_textTertiary = getColor(paletteObj,
        {QStringLiteral("textTertiary"), QStringLiteral("on_surface_variant"), QStringLiteral("outline")},
        m_textTertiary);

    m_textDisabled = getColor(paletteObj,
        {QStringLiteral("textDisabled"), QStringLiteral("outline")},
        m_textDisabled);

    m_textSubtle = getColor(paletteObj,
        {QStringLiteral("textSubtle"), QStringLiteral("on_surface_variant"), QStringLiteral("outline")},
        m_textSubtle);

    m_textDim = getColor(paletteObj,
        {QStringLiteral("textDim"), QStringLiteral("on_surface_variant")},
        m_textDim);

    // 4. Accent & Highlights
    m_accent = getColor(paletteObj,
        {QStringLiteral("accent"), QStringLiteral("primary")},
        m_accent);

    m_accentSoft = getColor(paletteObj,
        {QStringLiteral("accentSoft"), QStringLiteral("primary_container"), QStringLiteral("secondary")},
        m_accentSoft);

    m_accentPressed = getColor(paletteObj,
        {QStringLiteral("accentPressed"), QStringLiteral("inverse_primary")},
        m_accent.darker(125));

    // Contrast text for accent backgrounds
    if (paletteObj.contains(QStringLiteral("textOnAccent")) || paletteObj.contains(QStringLiteral("on_primary"))) {
        m_textOnAccent = getColor(paletteObj, {QStringLiteral("textOnAccent"), QStringLiteral("on_primary")}, Qt::white);
    } else {
        const qreal luminance = 0.299 * m_accent.redF() + 0.587 * m_accent.greenF() + 0.114 * m_accent.blueF();
        m_textOnAccent = luminance > 0.6 ? hex("#140c09") : Qt::white;
    }

    // 5. Semantic statuses
    m_success = getColor(paletteObj, {QStringLiteral("success"), QStringLiteral("tertiary")}, m_success);
    m_warning = getColor(paletteObj, {QStringLiteral("warning"), QStringLiteral("tertiary_container")}, m_warning);
    m_danger = getColor(paletteObj, {QStringLiteral("danger"), QStringLiteral("error")}, m_danger);
    m_error = getColor(paletteObj, {QStringLiteral("error"), QStringLiteral("danger")}, m_error);
    m_disabledControl = getColor(paletteObj, {QStringLiteral("disabledControl"), QStringLiteral("outline")}, m_disabledControl);
    m_switchOff = getColor(paletteObj, {QStringLiteral("switchOff"), QStringLiteral("outline_variant"), QStringLiteral("surface_variant")}, m_switchOff);

    // 6. Buttons
    m_buttonFill = getColor(paletteObj, {QStringLiteral("buttonFill"), QStringLiteral("on_surface")}, m_buttonFill);
    m_buttonFillHover = getColor(paletteObj, {QStringLiteral("buttonFillHover"), QStringLiteral("surface_bright")}, Qt::white);
    m_buttonFillPressed = getColor(paletteObj, {QStringLiteral("buttonFillPressed"), QStringLiteral("on_surface_variant")}, m_buttonFillPressed);

    // 7. Workspace & Overview
    QColor ovCard = m_panel;
    ovCard.setAlpha(0xee);
    m_overviewCard = getColor(paletteObj, {QStringLiteral("overviewCard")}, ovCard);

    QColor ovBorder = getColor(paletteObj, {QStringLiteral("outline_variant")}, QColor(255, 255, 255));
    ovBorder.setAlpha(0x33);
    m_overviewBorder = getColor(paletteObj, {QStringLiteral("overviewBorder")}, ovBorder);

    m_workspaceCell = getColor(paletteObj,
        {QStringLiteral("workspaceCell"), QStringLiteral("surface_container_low"), QStringLiteral("module")},
        m_workspaceCell);

    m_workspaceCellHover = getColor(paletteObj,
        {QStringLiteral("workspaceCellHover"), QStringLiteral("surface_container"), QStringLiteral("moduleHover")},
        m_workspaceCellHover);

    m_workspaceCellBorder = getColor(paletteObj,
        {QStringLiteral("workspaceCellBorder"), QStringLiteral("outline_variant")},
        m_workspaceCellBorder);

    m_workspaceCellBorderHover = getColor(paletteObj,
        {QStringLiteral("workspaceCellBorderHover"), QStringLiteral("primary"), QStringLiteral("accent")},
        m_workspaceCellBorderHover);

    m_workspaceActiveBorder = getColor(paletteObj,
        {QStringLiteral("workspaceActiveBorder"), QStringLiteral("primary"), QStringLiteral("accent")},
        m_workspaceActiveBorder);

    // 8. Battery Colors & Matugen Theme Mapping
    m_batteryCharging = getColor(paletteObj,
        {QStringLiteral("batteryCharging"), QStringLiteral("battery_charging"), QStringLiteral("success"), QStringLiteral("primary")},
        m_batteryCharging);

    m_batteryHigh = getColor(paletteObj,
        {QStringLiteral("batteryHigh"), QStringLiteral("battery_high"), QStringLiteral("success"), QStringLiteral("primary")},
        m_batteryHigh);

    m_batteryMedium = getColor(paletteObj,
        {QStringLiteral("batteryMedium"), QStringLiteral("battery_medium"), QStringLiteral("secondary"), QStringLiteral("tertiary")},
        m_batteryMedium);

    m_batteryLow = getColor(paletteObj,
        {QStringLiteral("batteryLow"), QStringLiteral("battery_low"), QStringLiteral("warning"), QStringLiteral("tertiary")},
        m_batteryLow);

    m_batteryCritical = getColor(paletteObj,
        {QStringLiteral("batteryCritical"), QStringLiteral("battery_critical"), QStringLiteral("danger"), QStringLiteral("error")},
        m_batteryCritical);

    auto contrastFor = [](const QColor &bg) -> QColor {
        const qreal lum = 0.299 * bg.redF() + 0.587 * bg.greenF() + 0.114 * bg.blueF();
        return lum > 0.6 ? hex("#140c09") : Qt::white;
    };

    m_textOnBatteryCharging = getColor(paletteObj,
        {QStringLiteral("textOnBatteryCharging"), QStringLiteral("on_primary")},
        contrastFor(m_batteryCharging));

    m_textOnBatteryHigh = getColor(paletteObj,
        {QStringLiteral("textOnBatteryHigh"), QStringLiteral("on_primary")},
        contrastFor(m_batteryHigh));

    m_textOnBatteryMedium = getColor(paletteObj,
        {QStringLiteral("textOnBatteryMedium"), QStringLiteral("on_secondary"), QStringLiteral("on_tertiary")},
        contrastFor(m_batteryMedium));

    m_textOnBatteryLow = getColor(paletteObj,
        {QStringLiteral("textOnBatteryLow"), QStringLiteral("on_tertiary")},
        contrastFor(m_batteryLow));

    m_textOnBatteryCritical = getColor(paletteObj,
        {QStringLiteral("textOnBatteryCritical"), QStringLiteral("on_error")},
        contrastFor(m_batteryCritical));

    m_paletteLoaded = true;
    emit colorsChanged();
}

bool StyleTokensBackend::paletteLoaded() const { return m_paletteLoaded; }
QString StyleTokensBackend::colorsFilePath() const { return m_activeColorsFilePath; }

void StyleTokensBackend::reload()
{
    loadPalette();
}

QColor StyleTokensBackend::withAlpha(const QColor &color, qreal alpha) const
{
    QColor result = color;
    result.setAlphaF(std::clamp(alpha, 0.0, 1.0));
    return result;
}

QColor StyleTokensBackend::transparent() const { return Qt::transparent; }
QColor StyleTokensBackend::black() const { return Qt::black; }
QColor StyleTokensBackend::white() const { return Qt::white; }
QColor StyleTokensBackend::clearBlack() const { return QColor(0, 0, 0, 0); }

QColor StyleTokensBackend::panel() const { return m_panel; }
QColor StyleTokensBackend::surfaceBorder() const { return m_surfaceBorder; }
QColor StyleTokensBackend::surfaceHighlight() const { return m_surfaceHighlight; }
QColor StyleTokensBackend::module() const { return m_module; }
QColor StyleTokensBackend::moduleHover() const { return m_moduleHover; }
QColor StyleTokensBackend::track() const { return m_track; }
QColor StyleTokensBackend::cardFill() const { return m_cardFill; }
QColor StyleTokensBackend::cardFillActive() const { return m_cardFillActive; }
QColor StyleTokensBackend::cardFillHover() const { return m_cardFillHover; }
QColor StyleTokensBackend::connectivityCard() const { return m_connectivityCard; }
QColor StyleTokensBackend::connectivityCardHover() const { return m_connectivityCardHover; }
QColor StyleTokensBackend::prompt() const { return m_prompt; }
QColor StyleTokensBackend::input() const { return m_input; }
QColor StyleTokensBackend::inputBorder() const { return m_inputBorder; }
QColor StyleTokensBackend::secondaryButton() const { return m_secondaryButton; }

QColor StyleTokensBackend::textPrimary() const { return m_textPrimary; }
QColor StyleTokensBackend::textPrimaryBright() const { return m_textPrimaryBright; }
QColor StyleTokensBackend::textSecondary() const { return m_textSecondary; }
QColor StyleTokensBackend::textMuted() const { return m_textMuted; }
QColor StyleTokensBackend::textSoft() const { return m_textSoft; }
QColor StyleTokensBackend::textTertiary() const { return m_textTertiary; }
QColor StyleTokensBackend::textDisabled() const { return m_textDisabled; }
QColor StyleTokensBackend::textSubtle() const { return m_textSubtle; }
QColor StyleTokensBackend::textDim() const { return m_textDim; }

QColor StyleTokensBackend::accent() const { return m_accent; }
QColor StyleTokensBackend::accentPressed() const { return m_accentPressed; }
QColor StyleTokensBackend::accentSoft() const { return m_accentSoft; }
QColor StyleTokensBackend::textOnAccent() const { return m_textOnAccent; }

QColor StyleTokensBackend::success() const { return m_success; }
QColor StyleTokensBackend::warning() const { return m_warning; }
QColor StyleTokensBackend::danger() const { return m_danger; }
QColor StyleTokensBackend::error() const { return m_error; }
QColor StyleTokensBackend::disabledControl() const { return m_disabledControl; }
QColor StyleTokensBackend::switchOff() const { return m_switchOff; }

QColor StyleTokensBackend::buttonFill() const { return m_buttonFill; }
QColor StyleTokensBackend::buttonFillHover() const { return m_buttonFillHover; }
QColor StyleTokensBackend::buttonFillPressed() const { return m_buttonFillPressed; }

QColor StyleTokensBackend::overviewCard() const { return m_overviewCard; }
QColor StyleTokensBackend::overviewBorder() const { return m_overviewBorder; }
QColor StyleTokensBackend::overviewInnerBorder() const { return m_overviewInnerBorder; }
QColor StyleTokensBackend::workspaceCell() const { return m_workspaceCell; }
QColor StyleTokensBackend::workspaceCellHover() const { return m_workspaceCellHover; }
QColor StyleTokensBackend::workspaceCellBorder() const { return m_workspaceCellBorder; }
QColor StyleTokensBackend::workspaceCellBorderHover() const { return m_workspaceCellBorderHover; }
QColor StyleTokensBackend::workspaceOverlay() const { return m_workspaceOverlay; }
QColor StyleTokensBackend::workspaceOverlayHover() const { return m_workspaceOverlayHover; }
QColor StyleTokensBackend::workspaceActiveBorder() const { return m_workspaceActiveBorder; }

int StyleTokensBackend::radiusPanel() const { return 28; }
int StyleTokensBackend::radiusModule() const { return 20; }
int StyleTokensBackend::radiusPrompt() const { return 16; }
int StyleTokensBackend::radiusButton() const { return 12; }
int StyleTokensBackend::durationFast() const { return 120; }
int StyleTokensBackend::durationControl() const { return 130; }
int StyleTokensBackend::durationQuick() const { return 140; }
int StyleTokensBackend::durationStandard() const { return 240; }

QColor StyleTokensBackend::batteryCharging() const { return m_batteryCharging; }
QColor StyleTokensBackend::batteryHigh() const { return m_batteryHigh; }
QColor StyleTokensBackend::batteryMedium() const { return m_batteryMedium; }
QColor StyleTokensBackend::batteryLow() const { return m_batteryLow; }
QColor StyleTokensBackend::batteryCritical() const { return m_batteryCritical; }

QColor StyleTokensBackend::textOnBatteryCharging() const { return m_textOnBatteryCharging; }
QColor StyleTokensBackend::textOnBatteryHigh() const { return m_textOnBatteryHigh; }
QColor StyleTokensBackend::textOnBatteryMedium() const { return m_textOnBatteryMedium; }
QColor StyleTokensBackend::textOnBatteryLow() const { return m_textOnBatteryLow; }
QColor StyleTokensBackend::textOnBatteryCritical() const { return m_textOnBatteryCritical; }

QColor StyleTokensBackend::batteryColor(double level, bool charging) const
{
    if (charging)
        return m_batteryCharging;
    if (level >= 60.0)
        return m_batteryHigh;
    if (level >= 30.0)
        return m_batteryMedium;
    if (level >= 15.0)
        return m_batteryLow;
    return m_batteryCritical;
}

QColor StyleTokensBackend::batteryTextColor(double level, bool charging) const
{
    if (charging)
        return m_textOnBatteryCharging;
    if (level >= 60.0)
        return m_textOnBatteryHigh;
    if (level >= 30.0)
        return m_textOnBatteryMedium;
    if (level >= 15.0)
        return m_textOnBatteryLow;
    return m_textOnBatteryCritical;
}
