#pragma once

#include <QObject>
#include <QtQml/qqml.h>
#include <QString>
#include <QTimer>
#include <QElapsedTimer>

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
    Q_PROPERTY(QString avatarPath READ avatarPath WRITE setAvatarPath NOTIFY avatarPathChanged FINAL)

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
    QString avatarPath() const { return m_avatarPath; }

    Q_INVOKABLE void setAvatarPath(const QString &path);
    Q_INVOKABLE void openAvatarDirectory();
    Q_INVOKABLE void refreshNow();
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

    static SystemGlanceBackend *s_instance;

    bool m_active = false;
    QTimer m_pollTimer;
    QElapsedTimer m_lastNetTime;

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
    QString m_avatarPath;
};
