#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QtQml/qqml.h>

class StyleTokensBackend final : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(StyleTokens)
    QML_SINGLETON

    Q_PROPERTY(bool paletteLoaded READ paletteLoaded NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QString colorsFilePath READ colorsFilePath NOTIFY colorsChanged FINAL)

    Q_PROPERTY(QColor transparent READ transparent CONSTANT FINAL)
    Q_PROPERTY(QColor black READ black CONSTANT FINAL)
    Q_PROPERTY(QColor white READ white CONSTANT FINAL)
    Q_PROPERTY(QColor clearBlack READ clearBlack CONSTANT FINAL)

    Q_PROPERTY(QColor panel READ panel NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor surfaceBorder READ surfaceBorder NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor surfaceHighlight READ surfaceHighlight NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor module READ module NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor moduleHover READ moduleHover NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor track READ track NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor cardFill READ cardFill NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor cardFillActive READ cardFillActive NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor cardFillHover READ cardFillHover NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor card READ cardFill NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor cardHover READ cardFillHover NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor connectivityCard READ connectivityCard NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor connectivityCardHover READ connectivityCardHover NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor prompt READ prompt NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor input READ input NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor inputBorder READ inputBorder NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor secondaryButton READ secondaryButton NOTIFY colorsChanged FINAL)

    Q_PROPERTY(QColor textPrimary READ textPrimary NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textPrimaryBright READ textPrimaryBright NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textSecondary READ textSecondary NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textMuted READ textMuted NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textSoft READ textSoft NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textTertiary READ textTertiary NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textDisabled READ textDisabled NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textSubtle READ textSubtle NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textDim READ textDim NOTIFY colorsChanged FINAL)

    Q_PROPERTY(QColor accent READ accent NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor accentPressed READ accentPressed NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor accentSoft READ accentSoft NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textOnAccent READ textOnAccent NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor success READ success NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor warning READ warning NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor danger READ danger NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor error READ error NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor disabledControl READ disabledControl NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor switchOff READ switchOff NOTIFY colorsChanged FINAL)

    Q_PROPERTY(QColor buttonFill READ buttonFill NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor buttonFillHover READ buttonFillHover NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor buttonFillPressed READ buttonFillPressed NOTIFY colorsChanged FINAL)

    Q_PROPERTY(QColor batteryCharging READ batteryCharging NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor batteryHigh READ batteryHigh NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor batteryMedium READ batteryMedium NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor batteryLow READ batteryLow NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor batteryCritical READ batteryCritical NOTIFY colorsChanged FINAL)

    Q_PROPERTY(QColor textOnBatteryCharging READ textOnBatteryCharging NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textOnBatteryHigh READ textOnBatteryHigh NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textOnBatteryMedium READ textOnBatteryMedium NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textOnBatteryLow READ textOnBatteryLow NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor textOnBatteryCritical READ textOnBatteryCritical NOTIFY colorsChanged FINAL)

    Q_PROPERTY(QColor overviewCard READ overviewCard NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor overviewBorder READ overviewBorder NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor overviewInnerBorder READ overviewInnerBorder NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor workspaceCell READ workspaceCell NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor workspaceCellHover READ workspaceCellHover NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor workspaceCellBorder READ workspaceCellBorder NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor workspaceCellBorderHover READ workspaceCellBorderHover NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor workspaceOverlay READ workspaceOverlay NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor workspaceOverlayHover READ workspaceOverlayHover NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor workspaceActiveBorder READ workspaceActiveBorder NOTIFY colorsChanged FINAL)

    Q_PROPERTY(int radiusPanel READ radiusPanel CONSTANT FINAL)
    Q_PROPERTY(int radiusModule READ radiusModule CONSTANT FINAL)
    Q_PROPERTY(int radiusPrompt READ radiusPrompt CONSTANT FINAL)
    Q_PROPERTY(int radiusButton READ radiusButton CONSTANT FINAL)
    Q_PROPERTY(int durationFast READ durationFast CONSTANT FINAL)
    Q_PROPERTY(int durationControl READ durationControl CONSTANT FINAL)
    Q_PROPERTY(int durationQuick READ durationQuick CONSTANT FINAL)
    Q_PROPERTY(int durationStandard READ durationStandard CONSTANT FINAL)

public:
    explicit StyleTokensBackend(QObject *parent = nullptr);

    bool paletteLoaded() const;
    QString colorsFilePath() const;

    QColor transparent() const;
    QColor black() const;
    QColor white() const;
    QColor clearBlack() const;
    QColor panel() const;
    QColor surfaceBorder() const;
    QColor surfaceHighlight() const;
    QColor module() const;
    QColor moduleHover() const;
    QColor track() const;
    QColor cardFill() const;
    QColor cardFillActive() const;
    QColor cardFillHover() const;
    QColor connectivityCard() const;
    QColor connectivityCardHover() const;
    QColor prompt() const;
    QColor input() const;
    QColor inputBorder() const;
    QColor secondaryButton() const;
    QColor textPrimary() const;
    QColor textPrimaryBright() const;
    QColor textSecondary() const;
    QColor textMuted() const;
    QColor textSoft() const;
    QColor textTertiary() const;
    QColor textDisabled() const;
    QColor textSubtle() const;
    QColor textDim() const;
    QColor accent() const;
    QColor accentPressed() const;
    QColor accentSoft() const;
    QColor textOnAccent() const;
    QColor success() const;
    QColor warning() const;
    QColor danger() const;
    QColor error() const;
    QColor disabledControl() const;
    QColor switchOff() const;
    QColor buttonFill() const;
    QColor buttonFillHover() const;
    QColor buttonFillPressed() const;
    QColor batteryCharging() const;
    QColor batteryHigh() const;
    QColor batteryMedium() const;
    QColor batteryLow() const;
    QColor batteryCritical() const;
    QColor textOnBatteryCharging() const;
    QColor textOnBatteryHigh() const;
    QColor textOnBatteryMedium() const;
    QColor textOnBatteryLow() const;
    QColor textOnBatteryCritical() const;
    QColor overviewCard() const;
    QColor overviewBorder() const;
    QColor overviewInnerBorder() const;
    QColor workspaceCell() const;
    QColor workspaceCellHover() const;
    QColor workspaceCellBorder() const;
    QColor workspaceCellBorderHover() const;
    QColor workspaceOverlay() const;
    QColor workspaceOverlayHover() const;
    QColor workspaceActiveBorder() const;

    int radiusPanel() const;
    int radiusModule() const;
    int radiusPrompt() const;
    int radiusButton() const;
    int durationFast() const;
    int durationControl() const;
    int durationQuick() const;
    int durationStandard() const;

    Q_INVOKABLE QColor withAlpha(const QColor &color, qreal alpha) const;
    Q_INVOKABLE QColor batteryColor(double level, bool charging) const;
    Q_INVOKABLE QColor batteryTextColor(double level, bool charging) const;
    Q_INVOKABLE void reload();

signals:
    void colorsChanged();

private:
    void initDefaults();
    void loadPalette();
    void scheduleReload();
    void updateWatchedPaths();
    QString resolveConfigHome() const;
    QString defaultColorsFilePath() const;
    QString effectiveColorsFilePath() const;

    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;
    bool m_paletteLoaded = false;
    QString m_activeColorsFilePath;

    QColor m_panel;
    QColor m_surfaceBorder;
    QColor m_surfaceHighlight;
    QColor m_module;
    QColor m_moduleHover;
    QColor m_track;
    QColor m_cardFill;
    QColor m_cardFillActive;
    QColor m_cardFillHover;
    QColor m_connectivityCard;
    QColor m_connectivityCardHover;
    QColor m_prompt;
    QColor m_input;
    QColor m_inputBorder;
    QColor m_secondaryButton;
    QColor m_textPrimary;
    QColor m_textPrimaryBright;
    QColor m_textSecondary;
    QColor m_textMuted;
    QColor m_textSoft;
    QColor m_textTertiary;
    QColor m_textDisabled;
    QColor m_textSubtle;
    QColor m_textDim;
    QColor m_accent;
    QColor m_accentPressed;
    QColor m_accentSoft;
    QColor m_textOnAccent;
    QColor m_success;
    QColor m_warning;
    QColor m_danger;
    QColor m_error;
    QColor m_disabledControl;
    QColor m_switchOff;
    QColor m_buttonFill;
    QColor m_buttonFillHover;
    QColor m_buttonFillPressed;
    QColor m_overviewCard;
    QColor m_overviewBorder;
    QColor m_overviewInnerBorder;
    QColor m_workspaceCell;
    QColor m_workspaceCellHover;
    QColor m_workspaceCellBorder;
    QColor m_workspaceCellBorderHover;
    QColor m_workspaceOverlay;
    QColor m_workspaceOverlayHover;
    QColor m_workspaceActiveBorder;

    QColor m_batteryCharging;
    QColor m_batteryHigh;
    QColor m_batteryMedium;
    QColor m_batteryLow;
    QColor m_batteryCritical;
    QColor m_textOnBatteryCharging;
    QColor m_textOnBatteryHigh;
    QColor m_textOnBatteryMedium;
    QColor m_textOnBatteryLow;
    QColor m_textOnBatteryCritical;
};
