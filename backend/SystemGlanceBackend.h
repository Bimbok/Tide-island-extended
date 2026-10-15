#pragma once

#include <QObject>
#include <QtQml/qqml.h>
#include <QString>
#include <QTimer>
#include <QElapsedTimer>
#include <QFileSystemWatcher>
#include <QProcess>
#include <QPointer>

class SystemGlanceBackend : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(SystemGlance)
    QML_SINGLETON

    Q_PROPERTY(bool active READ isActive WRITE setActive NOTIFY activeChanged FINAL)

    // CPU
    Q_PROPERTY(double cpuUsage READ cpuUsage NOTIFY statsUpdated FINAL)
    Q_PROPERTY(int cpuTemperature READ cpuTemperature NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString cpuModel READ cpuModel NOTIFY staticInfoReady FINAL)

    // Memory
    Q_PROPERTY(double memoryUsagePercent READ memoryUsagePercent NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double memoryUsedGb READ memoryUsedGb NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double memoryTotalGb READ memoryTotalGb NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString memoryText READ memoryText NOTIFY statsUpdated FINAL)

    // Swap / ZRAM
    Q_PROPERTY(bool hasSwap READ hasSwap NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double swapUsagePercent READ swapUsagePercent NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double swapUsedGb READ swapUsedGb NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double swapTotalGb READ swapTotalGb NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString swapText READ swapText NOTIFY statsUpdated FINAL)

    // Package Updates
    Q_PROPERTY(int pendingUpdatesCount READ pendingUpdatesCount NOTIFY updatesChanged FINAL)
    Q_PROPERTY(bool checkingUpdates READ checkingUpdates NOTIFY updatesChanged FINAL)

    // GPU
    Q_PROPERTY(bool gpuAvailable READ gpuAvailable NOTIFY staticInfoReady FINAL)
    Q_PROPERTY(QString gpuName READ gpuName NOTIFY staticInfoReady FINAL)
    Q_PROPERTY(double gpuUsage READ gpuUsage NOTIFY statsUpdated FINAL)
    Q_PROPERTY(int gpuTemperature READ gpuTemperature NOTIFY statsUpdated FINAL)

    // Storage
    Q_PROPERTY(double diskUsagePercent READ diskUsagePercent NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double diskUsedGb READ diskUsedGb NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double diskTotalGb READ diskTotalGb NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString diskText READ diskText NOTIFY statsUpdated FINAL)

    // Network Throughput
    Q_PROPERTY(double downloadBytesPerSec READ downloadBytesPerSec NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double uploadBytesPerSec READ uploadBytesPerSec NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString downloadSpeedText READ downloadSpeedText NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString uploadSpeedText READ uploadSpeedText NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString networkInterface READ networkInterface NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString ipAddress READ ipAddress NOTIFY statsUpdated FINAL)
    Q_PROPERTY(bool vpnActive READ vpnActive NOTIFY statsUpdated FINAL)

    // System Identity
    Q_PROPERTY(QString userName READ userName NOTIFY staticInfoReady FINAL)
    Q_PROPERTY(QString hostName READ hostName NOTIFY staticInfoReady FINAL)
    Q_PROPERTY(QString uptimeText READ uptimeText NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString osName READ osName NOTIFY staticInfoReady FINAL)
    Q_PROPERTY(QString kernelVersion READ kernelVersion NOTIFY staticInfoReady FINAL)
    Q_PROPERTY(QString kernelRelease READ kernelRelease NOTIFY staticInfoReady FINAL)
    Q_PROPERTY(QString kernelArch READ kernelArch NOTIFY staticInfoReady FINAL)
    Q_PROPERTY(QString avatarPath READ avatarPath WRITE setAvatarPath NOTIFY avatarPathChanged FINAL)

    // Kernel & Load Telemetry
    Q_PROPERTY(QString loadAvgText READ loadAvgText NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double loadAvg1 READ loadAvg1 NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double loadAvg5 READ loadAvg5 NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double loadAvg15 READ loadAvg15 NOTIFY statsUpdated FINAL)
    Q_PROPERTY(int runningTasks READ runningTasks NOTIFY statsUpdated FINAL)
    Q_PROPERTY(int totalTasks READ totalTasks NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString tasksText READ tasksText NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString cpuGovernor READ cpuGovernor NOTIFY statsUpdated FINAL)

    // Battery Telemetry
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY statsUpdated FINAL)
    Q_PROPERTY(int batteryCapacity READ batteryCapacity NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString batteryStatus READ batteryStatus NOTIFY statsUpdated FINAL)
    Q_PROPERTY(double batteryPowerWatts READ batteryPowerWatts NOTIFY statsUpdated FINAL)
    Q_PROPERTY(QString batteryRateText READ batteryRateText NOTIFY statsUpdated FINAL)
    Q_PROPERTY(int batteryHealthPercent READ batteryHealthPercent NOTIFY statsUpdated FINAL)
    Q_PROPERTY(int batteryCycleCount READ batteryCycleCount NOTIFY statsUpdated FINAL)
    Q_PROPERTY(bool batteryConservationActive READ batteryConservationActive NOTIFY statsUpdated FINAL)

public:
    explicit SystemGlanceBackend(QObject *parent = nullptr);
    ~SystemGlanceBackend() override;

    static SystemGlanceBackend *instance();

    bool isActive() const { return m_active; }
    void setActive(bool active);

    double cpuUsage() const { return m_cpuUsage; }
    int cpuTemperature() const { return m_cpuTemperature; }
    QString cpuModel() const { return m_cpuModel; }

    double memoryUsagePercent() const { return m_memoryUsagePercent; }
    double memoryUsedGb() const { return m_memoryUsedGb; }
    double memoryTotalGb() const { return m_memoryTotalGb; }
    QString memoryText() const { return m_memoryText; }

    bool hasSwap() const { return m_swapTotalGb > 0.05; }
    double swapUsagePercent() const { return m_swapUsagePercent; }
    double swapUsedGb() const { return m_swapUsedGb; }
    double swapTotalGb() const { return m_swapTotalGb; }
    QString swapText() const { return m_swapText; }

    int pendingUpdatesCount() const { return m_pendingUpdatesCount; }
    bool checkingUpdates() const { return m_checkingUpdates; }

    bool gpuAvailable() const { return m_gpuAvailable; }
    QString gpuName() const { return m_gpuName; }
    double gpuUsage() const { return m_gpuUsage; }
    int gpuTemperature() const { return m_gpuTemperature; }

    double diskUsagePercent() const { return m_diskUsagePercent; }
    double diskUsedGb() const { return m_diskUsedGb; }
    double diskTotalGb() const { return m_diskTotalGb; }
    QString diskText() const { return m_diskText; }

    double downloadBytesPerSec() const { return m_downloadBytesPerSec; }
    double uploadBytesPerSec() const { return m_uploadBytesPerSec; }
    QString downloadSpeedText() const { return m_downloadSpeedText; }
    QString uploadSpeedText() const { return m_uploadSpeedText; }
    QString networkInterface() const { return m_networkInterface; }
    QString ipAddress() const { return m_ipAddress; }
    bool vpnActive() const { return m_vpnActive; }

    QString userName() const { return m_userName; }
    QString hostName() const { return m_hostName; }
    QString uptimeText() const { return m_uptimeText; }
    QString osName() const { return m_osName; }
    QString kernelVersion() const { return m_kernelVersion; }
    QString kernelRelease() const { return m_kernelRelease; }
    QString kernelArch() const { return m_kernelArch; }
    QString avatarPath() const { return m_avatarPath; }

    QString loadAvgText() const { return m_loadAvgText; }
    double loadAvg1() const { return m_loadAvg1; }
    double loadAvg5() const { return m_loadAvg5; }
    double loadAvg15() const { return m_loadAvg15; }
    int runningTasks() const { return m_runningTasks; }
    int totalTasks() const { return m_totalTasks; }
    QString tasksText() const { return m_tasksText; }
    QString cpuGovernor() const { return m_cpuGovernor; }

    bool hasBattery() const { return m_hasBattery; }
    int batteryCapacity() const { return m_batteryCapacity; }
    QString batteryStatus() const { return m_batteryStatus; }
    double batteryPowerWatts() const { return m_batteryPowerWatts; }
    QString batteryRateText() const { return m_batteryRateText; }
    int batteryHealthPercent() const { return m_batteryHealthPercent; }
    int batteryCycleCount() const { return m_batteryCycleCount; }
    bool batteryConservationActive() const { return m_batteryConservationActive; }

    Q_INVOKABLE void setAvatarPath(const QString &path);
    Q_INVOKABLE void openAvatarDirectory();
    Q_INVOKABLE void refreshNow();
    Q_INVOKABLE void checkUpdatesAsync(bool force = false);
    Q_INVOKABLE void launchUpdateTerminal();
    Q_INVOKABLE void lockScreen();
    Q_INVOKABLE void suspendSystem();
    Q_INVOKABLE void rebootSystem();
    Q_INVOKABLE void powerOffSystem();

    static QString formatSpeed(double bytesPerSec);
    static QString formatUptime(quint64 uptimeSeconds);

signals:
    void activeChanged(bool active);
    void statsUpdated();
    void staticInfoReady();
    void avatarPathChanged();
    void updatesChanged();

private slots:
    void onPollTick();

private:
    void initStaticInfo();
    void updateCpu();
    void updateMemory();
    void updateGpu();
    void updateDisk();
    void updateNetwork();
    void updateUptime();
    void updateKernelStats();
    void updateBatteryStats();
    int readCpuTemperature();
    void reloadAvatar();

    static SystemGlanceBackend *s_instance;

    bool m_active = false;
    QTimer m_pollTimer;
    QElapsedTimer m_lastNetTime;
    QFileSystemWatcher m_configWatcher;

    // CPU state
    double m_cpuUsage = 0.0;
    int m_cpuTemperature = 0;
    QString m_cpuModel;
    quint64 m_prevCpuTotal = 0;
    quint64 m_prevCpuIdle = 0;

    // Memory state
    double m_memoryUsagePercent = 0.0;
    double m_memoryUsedGb = 0.0;
    double m_memoryTotalGb = 0.0;
    QString m_memoryText;

    // Swap state
    double m_swapUsagePercent = 0.0;
    double m_swapUsedGb = 0.0;
    double m_swapTotalGb = 0.0;
    QString m_swapText;

    // Updates state
    int m_pendingUpdatesCount = 0;
    bool m_checkingUpdates = false;
    QElapsedTimer m_lastUpdateCheckTime;
    QDateTime m_lastPacmanLogTime;
    QFileSystemWatcher m_pacmanWatcher;
    QPointer<QProcess> m_updateProcess;

    // GPU state
    bool m_gpuAvailable = false;
    QString m_gpuName;
    double m_gpuUsage = 0.0;
    int m_gpuTemperature = 0;

    // Disk state
    double m_diskUsagePercent = 0.0;
    double m_diskUsedGb = 0.0;
    double m_diskTotalGb = 0.0;
    QString m_diskText;

    // Network state
    double m_downloadBytesPerSec = 0.0;
    double m_uploadBytesPerSec = 0.0;
    QString m_downloadSpeedText = QStringLiteral("↓ 0 B/s");
    QString m_uploadSpeedText = QStringLiteral("↑ 0 B/s");
    QString m_networkInterface = QStringLiteral("wlan0");
    QString m_ipAddress = QStringLiteral("127.0.0.1");
    bool m_vpnActive = false;
    quint64 m_prevRxBytes = 0;
    quint64 m_prevTxBytes = 0;

    // System Identity state
    QString m_userName;
    QString m_hostName;
    QString m_uptimeText;
    QString m_osName;
    QString m_kernelVersion;
    QString m_kernelRelease;
    QString m_kernelArch;
    QString m_avatarPath;

    // Kernel & Load state
    QString m_cpuGovernor = QStringLiteral("powersave");
    QString m_loadAvgText = QStringLiteral("0.00, 0.00, 0.00");
    double m_loadAvg1 = 0.0;
    double m_loadAvg5 = 0.0;
    double m_loadAvg15 = 0.0;
    int m_runningTasks = 0;
    int m_totalTasks = 0;
    QString m_tasksText = QStringLiteral("0 tasks");

    // Battery state
    bool m_hasBattery = false;
    int m_batteryCapacity = 0;
    QString m_batteryStatus = QStringLiteral("Unknown");
    double m_batteryPowerWatts = 0.0;
    QString m_batteryRateText = QStringLiteral("0.0 W");
    int m_batteryHealthPercent = 100;
    int m_batteryCycleCount = 0;
    bool m_batteryConservationActive = false;
};
