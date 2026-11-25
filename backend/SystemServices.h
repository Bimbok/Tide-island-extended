#pragma once

#include <QObject>
#include <QByteArray>
#include <QPointer>
#include <QProcess>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <QtQml/qqml.h>

#include <functional>

class SystemServices final : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool screenRecordingActive READ screenRecordingActive NOTIFY screenRecordingActiveChanged FINAL)
    Q_PROPERTY(bool micActive READ micActive NOTIFY privacyIndicatorsChanged FINAL)
    Q_PROPERTY(bool cameraActive READ cameraActive NOTIFY privacyIndicatorsChanged FINAL)
    Q_PROPERTY(bool privacyActive READ privacyActive NOTIFY privacyIndicatorsChanged FINAL)
    Q_PROPERTY(QVariantList activePrivacyApps READ activePrivacyApps NOTIFY privacyIndicatorsChanged FINAL)
    Q_PROPERTY(QVariantList cavaLevels READ cavaLevels NOTIFY cavaLevelsChanged FINAL)
    Q_PROPERTY(QVariantList audioOutputs READ audioOutputs NOTIFY audioOutputsChanged FINAL)
    Q_PROPERTY(bool isMultiOutputActive READ isMultiOutputActive NOTIFY isMultiOutputActiveChanged FINAL)
    Q_PROPERTY(int activeOutputCount READ activeOutputCount NOTIFY activeOutputCountChanged FINAL)
    Q_PROPERTY(QVariantList audioInputs READ audioInputs NOTIFY audioInputsChanged FINAL)
    Q_PROPERTY(QVariantList appStreams READ appStreams NOTIFY appStreamsChanged FINAL)
    Q_PROPERTY(QString defaultAudioSink READ defaultAudioSink NOTIFY defaultAudioSinkChanged FINAL)
    Q_PROPERTY(QString defaultAudioSource READ defaultAudioSource NOTIFY defaultAudioSourceChanged FINAL)
    Q_PROPERTY(bool equalizerAvailable READ equalizerAvailable NOTIFY equalizerAvailableChanged FINAL)
    Q_PROPERTY(bool equalizerRunning READ equalizerRunning NOTIFY equalizerRunningChanged FINAL)
    Q_PROPERTY(bool equalizerEnabled READ equalizerEnabled WRITE setEqualizerEnabled NOTIFY equalizerEnabledChanged FINAL)
    Q_PROPERTY(QVariantList equalizerBands READ equalizerBands WRITE setEqualizerBands NOTIFY equalizerBandsChanged FINAL)
    Q_PROPERTY(QString equalizerPreset READ equalizerPreset WRITE applyEqualizerPreset NOTIFY equalizerPresetChanged FINAL)
    Q_PROPERTY(double equalizerBalance READ equalizerBalance WRITE setEqualizerBalance NOTIFY equalizerBalanceChanged FINAL)
    Q_PROPERTY(bool equalizerMono READ equalizerMono WRITE setEqualizerMono NOTIFY equalizerMonoChanged FINAL)
    Q_PROPERTY(QString equalizerDynamics READ equalizerDynamics WRITE setEqualizerDynamics NOTIFY equalizerDynamicsChanged FINAL)
    Q_PROPERTY(bool batteryThresholdSupported READ batteryThresholdSupported NOTIFY batteryThresholdChanged FINAL)
    Q_PROPERTY(QString batteryThresholdType READ batteryThresholdType NOTIFY batteryThresholdChanged FINAL)
    Q_PROPERTY(bool batteryConservationMode READ batteryConservationMode NOTIFY batteryThresholdChanged FINAL)
    Q_PROPERTY(int batteryThresholdValue READ batteryThresholdValue NOTIFY batteryThresholdChanged FINAL)
    Q_PROPERTY(QVariantList batteryThresholdPresets READ batteryThresholdPresets NOTIFY batteryThresholdChanged FINAL)
    Q_PROPERTY(bool batteryThresholdBusy READ batteryThresholdBusy NOTIFY batteryThresholdBusyChanged FINAL)
    Q_PROPERTY(QString batteryThresholdError READ batteryThresholdError NOTIFY batteryThresholdChanged FINAL)
    Q_PROPERTY(int batteryCycleCount READ batteryCycleCount NOTIFY batteryHealthMetricsChanged FINAL)
    Q_PROPERTY(int batteryHealthPercent READ batteryHealthPercent NOTIFY batteryHealthMetricsChanged FINAL)
    Q_PROPERTY(QString batteryChargeState READ batteryChargeState NOTIFY batteryHealthMetricsChanged FINAL)
    Q_PROPERTY(bool cliphistAvailable READ cliphistAvailable CONSTANT)
    Q_PROPERTY(bool externalClipboardWatcherRunning READ externalClipboardWatcherRunning CONSTANT)

public:
    explicit SystemServices(QObject *parent = nullptr);
    ~SystemServices() override;

    static SystemServices *instance();

    bool screenRecordingActive() const;
    bool micActive() const { return m_micActive; }
    bool cameraActive() const { return m_cameraActive; }
    bool privacyActive() const { return m_micActive || m_cameraActive; }
    bool cliphistAvailable() const { return m_cliphistAvailable; }
    bool externalClipboardWatcherRunning() const;
    Q_INVOKABLE bool isCapsLockActive() const;
    QVariantList activePrivacyApps() const { return m_activePrivacyApps; }
    QVariantList cavaLevels() const;
    QVariantList audioOutputs() const { return m_audioOutputs; }
    bool isMultiOutputActive() const { return m_isMultiOutputActive; }
    int activeOutputCount() const;
    QVariantList audioInputs() const { return m_audioInputs; }
    QVariantList appStreams() const { return m_appStreams; }
    QString defaultAudioSink() const { return m_defaultAudioSink; }
    QString defaultAudioSource() const { return m_defaultAudioSource; }
    bool equalizerAvailable() const;
    bool equalizerRunning() const { return m_equalizerRunning; }
    bool equalizerEnabled() const { return m_equalizerEnabled; }
    QVariantList equalizerBands() const { return m_equalizerBands; }
    QString equalizerPreset() const { return m_equalizerPreset; }
    double equalizerBalance() const { return m_equalizerBalance; }
    bool equalizerMono() const { return m_equalizerMono; }
    QString equalizerDynamics() const { return m_equalizerDynamics; }
    bool batteryThresholdSupported() const { return m_batteryThresholdSupported; }
    QString batteryThresholdType() const { return m_batteryThresholdType; }
    bool batteryConservationMode() const { return m_batteryConservationMode; }
    int batteryThresholdValue() const { return m_batteryThresholdValue; }
    QVariantList batteryThresholdPresets() const { return m_batteryThresholdPresets; }
    bool batteryThresholdBusy() const { return m_batteryThresholdBusy; }
    QString batteryThresholdError() const { return m_batteryThresholdError; }
    int batteryCycleCount() const { return m_batteryCycleCount; }
    int batteryHealthPercent() const { return m_batteryHealthPercent; }
    QString batteryChargeState() const { return m_batteryChargeState; }
    void updateScreenRecordingActive();

    Q_INVOKABLE void requestScreenRecordingSnapshot();
    Q_INVOKABLE void requestPrivacySnapshot();
    Q_INVOKABLE void requestHyprlandSnapshot(const QString &requestId, const QString &subject);
    Q_INVOKABLE void generateWallpaperThumbnail(const QString &sourcePath,
                                                const QString &cachePath,
                                                const QString &cacheDir,
                                                int targetWidth,
                                                int targetHeight,
                                                int quality);
    Q_INVOKABLE void requestBrightness();
    Q_INVOKABLE void setBrightness(double value);
    Q_INVOKABLE void requestVolume();
    Q_INVOKABLE void setVolume(double value);
    Q_INVOKABLE void toggleVolumeMute();
    Q_INVOKABLE void requestMicVolume();
    Q_INVOKABLE void setMicVolume(double value);
    Q_INVOKABLE void toggleMicMute();
    Q_INVOKABLE void requestAudioOutputs();
    Q_INVOKABLE void requestAudioInputs();
    Q_INVOKABLE void requestAppStreams();
    Q_INVOKABLE void setAudioOutput(const QString &sinkName, const QString &portName = QString());
    Q_INVOKABLE void toggleAudioOutput(const QString &sinkName, const QString &portName = QString());
    Q_INVOKABLE void setDeviceVolume(const QString &sinkName, double volume, const QString &portName = QString());
    Q_INVOKABLE void toggleDeviceMute(const QString &sinkName, const QString &portName = QString());
    Q_INVOKABLE void setAudioInput(const QString &sourceName, const QString &portName = QString());
    Q_INVOKABLE void setAppStreamVolume(int streamIndex, double volume);
    Q_INVOKABLE void toggleAppStreamMute(int streamIndex);
    Q_INVOKABLE void setAudioMonitoringActive(bool active);
    void refreshAudioIfActive();
    Q_INVOKABLE void requestEqualizerState();
    Q_INVOKABLE void setEqualizerEnabled(bool enabled);
    Q_INVOKABLE void setEqualizerBand(int index, double gain);
    Q_INVOKABLE void setEqualizerBands(const QVariantList &bands);
    Q_INVOKABLE void applyEqualizerPreset(const QString &presetName);
    Q_INVOKABLE void setEqualizerBalance(double balance);
    Q_INVOKABLE void setEqualizerMono(bool mono);
    Q_INVOKABLE void setEqualizerDynamics(const QString &dynamics);
    Q_INVOKABLE void resetEqualizer();
    Q_INVOKABLE void requestTlpState();
    Q_INVOKABLE void setTlpMode(const QString &mode,
                                const QString &sudoPassword = QString(),
                                bool promptForPassword = false);
    Q_INVOKABLE void cancelTlpApply();
    Q_INVOKABLE void requestPowerProfileState(const QString &driver = QString());
    Q_INVOKABLE void setPowerProfileMode(const QString &driver,
                                        const QString &mode,
                                        const QString &sudoPassword = QString(),
                                        bool promptForPassword = false);
    Q_INVOKABLE void cancelPowerProfileApply();
    Q_INVOKABLE void setCavaClientActive(const QString &clientId, bool active);
    Q_INVOKABLE void ensureUserConfigAvailable();
    Q_INVOKABLE void invokeNotificationAction(uint id, const QString &actionKey);
    Q_INVOKABLE void closeNotification(uint id, uint reason = 2);
    Q_INVOKABLE void copyToClipboard(const QString &text);
    Q_INVOKABLE void focusSenderWindow(const QString &appName,
                                       qint64 pid = 0,
                                       const QString &summary = QString(),
                                       const QString &body = QString());
    Q_INVOKABLE QList<qint64> processAncestorPids(qint64 pid) const;
    Q_INVOKABLE void requestBatteryThresholdState();
    Q_INVOKABLE void setBatteryConservationMode(bool enabled);
    Q_INVOKABLE void setBatteryThreshold(int threshold);
    Q_INVOKABLE double queryDiskUsagePercent(const QString &mountPath = QStringLiteral("/")) const;
    Q_INVOKABLE QString defaultTerminalEmulator() const;
    Q_INVOKABLE QStringList wrapTerminalCommand(const QStringList &command) const;
    Q_INVOKABLE bool launchApplication(const QStringList &command,
                                       bool runInTerminal = false,
                                       const QString &workingDirectory = QString()) const;

signals:
    void notificationReceived(uint id,
                              const QString &appName,
                              const QString &appIcon,
                              const QString &summary,
                              const QString &body,
                              const QVariantList &actions,
                              const QString &imagePath,
                              int urgency,
                              qint64 senderPid = 0);
    void screenRecordingActiveChanged();
    void privacyIndicatorsChanged();
    void hyprlandSnapshotReady(const QString &requestId,
                               const QString &subject,
                               const QString &payloadJson,
                               const QString &errorString);
    void wallpaperThumbnailFinished(const QString &sourcePath,
                                    const QString &cachePath,
                                    bool cacheAvailable,
                                    bool updated,
                                    const QString &errorString);
    void brightnessSnapshotReady(double value, const QString &errorString);
    void brightnessSetFinished(double value, bool success, const QString &errorString);
    void volumeSnapshotReady(double value, bool muted, const QString &errorString);
    void volumeSetFinished(double value, bool success, const QString &errorString);
    void micVolumeSnapshotReady(double value, bool muted, const QString &errorString);
    void micVolumeSetFinished(double value, bool success, const QString &errorString);
    void tlpStateReady(bool available, const QString &profile, const QString &output, const QString &errorString);
    void tlpSetFinished(bool success, int exitCode, const QString &output, const QString &errorString);
    void batteryThresholdChanged();
    void batteryThresholdBusyChanged();
    void batteryHealthMetricsChanged();
    void batteryThresholdFinished(bool success, const QString &errorString);
    void cavaLevelsChanged();
    void audioOutputsChanged();
    void isMultiOutputActiveChanged();
    void activeOutputCountChanged();
    void audioInputsChanged();
    void appStreamsChanged();
    void defaultAudioSinkChanged();
    void defaultAudioSourceChanged();
    void equalizerAvailableChanged();
    void equalizerRunningChanged();
    void equalizerEnabledChanged();
    void equalizerBandsChanged();
    void equalizerPresetChanged();
    void equalizerBalanceChanged();
    void equalizerMonoChanged();
    void equalizerDynamicsChanged();

private:
    struct CommandResult {
        int exitCode = -1;
        QProcess::ExitStatus exitStatus = QProcess::NormalExit;
        QByteArray stdoutData;
        QByteArray stderrData;
        QString errorString;
        bool timedOut = false;
    };

    using CommandCallback = std::function<void(const CommandResult &)>;

    QProcess *startCommand(const QString &program,
                           const QStringList &arguments,
                           int timeoutMs,
                           CommandCallback callback,
                           const QByteArray &stdinData = QByteArray());
    QString findExecutable(const QString &program) const;
    QString commandErrorText(const QString &program, const CommandResult &result) const;
    QString resolvePowerProfileDriver(const QString &requestedDriver) const;

    void detectBatteryThresholdSupport();
    void updateBatteryMetrics();
    void applyBatteryThresholdValue(const QString &targetValue);

    void startBusMonitor();
    void startNotificationMonitor();
    void startPipeWireMonitor();
    void startRecordingPortalMonitor();
    void stopProcess(QProcess *&process);
    void setPortalPipeWireActive(bool active);

    void handleBusMonitorOutput();
    void handleNotificationOutput();
    void handlePipeWireOutput();
    void handleRecordingPortalOutput();
    void processLines(QByteArray &buffer, const QByteArray &chunk, const std::function<void(const QString &)> &handler);
    void handleBusMonitorLine(const QString &line);
    Q_INVOKABLE void handleNotificationLine(const QString &line);
    void handlePipeWireLine(const QString &line);
    void handleRecordingPortalLine(const QString &line);
    void applyPipeWireSnapshot(const QString &text);
    Q_INVOKABLE void handlePrivacySnapshotOutput(const QString &output);

    bool extractDbusString(const QString &line, QString &result);
    QString decodeEscapedString(const QString &escaped) const;
    QString decodeDbusMonitorString(const QString &line) const;
    QString extractHeaderPath(const QString &line) const;
    QString extractObjectPath(const QString &line) const;
    QString cacheNotificationImage(const QString &sourcePath, uint notifId);
    bool screenCastMemberHasSessionArgument(const QString &memberName) const;
    bool pipeWireBlockLooksLikeScreenCast(const QString &blockText) const;

    double parseBrightnessOutput(const QString &text, bool *ok) const;
    void parseVolumeOutput(const QString &text, double *value, bool *muted, bool *ok) const;
    QString parseTlpProfile(const QString &text) const;

    void applyPendingBrightness();
    void applyPendingVolume();
    void applyPendingMicVolume();
    void applyPendingAppStreamVolume(int streamIndex);

    void startCava();
    void stopCava();
    void handleCavaOutput();
    void handleCavaLine(const QString &line);
    void updatePrivacyPollInterval();

    bool m_shuttingDown = false;

    QProcess *m_busMonitor = nullptr;
    QProcess *m_pipeWireMonitor = nullptr;
    QProcess *m_recordingSnapshot = nullptr;
    QProcess *m_tlpSetter = nullptr;
    QProcess *m_cavaProcess = nullptr;

    QTimer m_busMonitorRestartTimer;
    QTimer m_pipeWireRestartTimer;
    QTimer m_recordingSnapshotDebounceTimer;
    QTimer m_privacyPollTimer;
    QTimer m_cavaRestartTimer;

    QByteArray m_busMonitorBuffer;
    QByteArray m_pipeWireBuffer;
    QByteArray m_cavaBuffer;

    bool m_screenRecordingActive = false;
    bool m_portalPipeWireActive = false;
    bool m_micActive = false;
    bool m_cameraActive = false;
    bool m_cliphistAvailable = false;
    QVariantList m_activePrivacyApps;
    QSet<QString> m_activeScreenCastSessions;
    QString m_pendingScreenCastMember;
    QString m_pendingSessionCandidate;

    bool m_notificationCaptureActive = false;
    int m_notificationCaptureStage = -1;
    uint m_nextNotificationId = 1000;
    uint m_pendingNotificationId = 0;
    uint m_pendingNotificationReplacesId = 0;
    QString m_pendingNotificationAppName;
    QString m_pendingNotificationAppIcon;
    QString m_pendingNotificationSummary;
    QString m_pendingNotificationBody;
    QVariantList m_pendingNotificationActions;
    QString m_pendingNotificationActionKey;
    QString m_pendingNotificationImagePath;
    int m_pendingNotificationUrgency = 1;
    qint64 m_pendingNotificationSenderPid = 0;
    QString m_pendingHintKey;
    bool m_pendingNotificationInString = false;
    QString m_pendingNotificationStringAccumulator;

    qint64 m_lastCpuTotal = -1;
    qint64 m_lastCpuIdle = -1;

    QVariantList m_cavaLevels;
    QSet<QString> m_cavaClients;
    QSet<QString> m_wallpaperThumbnailRequests;
    bool m_cavaMissingWarned = false;
    int m_tlpCommandGeneration = 0;
    bool m_configAppLaunchRequested = false;

    bool m_brightnessRequestActive = false;
    bool m_brightnessSettingActive = false;
    double m_pendingBrightness = -1.0;
    double m_lastAppliedBrightness = -1.0;
    QTimer m_brightnessThrottleTimer;

    bool m_volumeRequestActive = false;
    bool m_volumeSettingActive = false;
    double m_pendingVolume = -1.0;
    double m_lastAppliedVolume = -1.0;
    QTimer m_volumeThrottleTimer;

    bool m_micVolumeRequestActive = false;
    bool m_micVolumeSettingActive = false;
    double m_pendingMicVolume = -1.0;
    double m_lastAppliedMicVolume = -1.0;
    QTimer m_micVolumeThrottleTimer;

    QVariantList m_audioOutputs;
    bool m_isMultiOutputActive = false;
    QStringList m_activeOutputDeviceIds;
    QString m_combinedSinkModuleId;
    bool m_combineSinkBusy = false;
    QStringList m_pendingCombineSinks;
    bool m_hasPendingCombine = false;
    bool m_headphonePortAvailable = false;
    void applyCombinedSink(const QStringList &sinks);
    QHash<QString, int> m_pendingSinkVolumePercents;
    QSet<QString> m_activeSinkVolumeCommands;
    void applyPendingSinkVolume(const QString &sinkName);
    QVariantList m_audioInputs;
    QVariantList m_appStreams;
    QString m_defaultAudioSink;
    QString m_defaultAudioSource;
    bool m_audioOutputsRequestActive = false;
    bool m_audioInputsRequestActive = false;
    bool m_appStreamsRequestActive = false;
    bool m_audioMonitoringActive = false;
    QHash<int, int> m_pendingAppStreamVolumePercents;
    QSet<int> m_activeAppStreamVolumeCommands;

    bool m_batteryThresholdSupported = false;
    QString m_batteryThresholdType;
    QString m_batteryThresholdSysfsPath;
    bool m_batteryConservationMode = false;
    int m_batteryThresholdValue = 100;
    QVariantList m_batteryThresholdPresets;
    bool m_batteryThresholdBusy = false;
    QString m_batteryThresholdError;
    int m_batteryCycleCount = 0;
    int m_batteryHealthPercent = 100;
    QString m_batteryChargeState;

    void initEqualizer();
    void parseEqualizerStateLine(const QString &line);
    void sendEqualizerCommand(const QString &command, std::function<void(bool success, const QString &reply)> callback = nullptr);
    void ensureEqualizerDaemon(std::function<void(bool running)> onReady = nullptr);
    void updateEqualizerPresetName();
    QString resolveEqualizerExecutable() const;

    bool m_equalizerRunning = false;
    bool m_equalizerEnabled = false;
    QString m_equalizerTargetSink;
    QVariantList m_equalizerBands;
    QString m_equalizerPreset = QStringLiteral("Flat");
    double m_equalizerBalance = 0.0;
    bool m_equalizerMono = false;
    bool m_equalizerSwap = false;
    QString m_equalizerDynamics = QStringLiteral("off");
    bool m_equalizerDyneq = false;
};
