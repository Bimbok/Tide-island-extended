#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>
#include <QtQml/qqml.h>

class ScreenRecorderController final : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(ScreenRecorder)
    QML_SINGLETON

    Q_PROPERTY(bool isRecording READ isRecording NOTIFY recordingStateChanged FINAL)
    Q_PROPERTY(bool isPaused READ isPaused NOTIFY recordingStateChanged FINAL)
    Q_PROPERTY(bool isReplayActive READ isReplayActive NOTIFY replayStateChanged FINAL)
    Q_PROPERTY(int recordingSeconds READ recordingSeconds NOTIFY recordingSecondsChanged FINAL)
    Q_PROPERTY(QString recordingTimeFormatted READ recordingTimeFormatted NOTIFY recordingSecondsChanged FINAL)
    Q_PROPERTY(bool micEnabled READ micEnabled WRITE setMicEnabled NOTIFY micEnabledChanged FINAL)
    Q_PROPERTY(int fps READ fps WRITE setFps NOTIFY fpsChanged FINAL)
    Q_PROPERTY(int replaySeconds READ replaySeconds WRITE setReplaySeconds NOTIFY replaySecondsChanged FINAL)
    Q_PROPERTY(QString screenName READ screenName WRITE setScreenName NOTIFY screenNameChanged FINAL)
    Q_PROPERTY(QString recordingsDir READ recordingsDir WRITE setRecordingsDir NOTIFY recordingsDirChanged FINAL)
    Q_PROPERTY(QString replaysDir READ replaysDir WRITE setReplaysDir NOTIFY replaysDirChanged FINAL)
    Q_PROPERTY(bool isAvailable READ isAvailable CONSTANT FINAL)
    Q_PROPERTY(QString lastSavedFile READ lastSavedFile NOTIFY lastSavedFileChanged FINAL)

public:
    explicit ScreenRecorderController(QObject *parent = nullptr);
    ~ScreenRecorderController() override;

    static ScreenRecorderController *instance();

    bool isRecording() const;
    bool isPaused() const;
    bool isReplayActive() const;
    int recordingSeconds() const;
    QString recordingTimeFormatted() const;
    bool micEnabled() const;
    void setMicEnabled(bool enabled);
    int fps() const;
    void setFps(int value);
    int replaySeconds() const;
    void setReplaySeconds(int value);
    QString screenName() const;
    void setScreenName(const QString &name);
    QString recordingsDir() const;
    void setRecordingsDir(const QString &dir);
    QString replaysDir() const;
    void setReplaysDir(const QString &dir);
    bool isAvailable() const;
    QString lastSavedFile() const;

    Q_INVOKABLE void startRecording(bool withMic = false);
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void toggleRecording();
    Q_INVOKABLE void pauseRecording();

    Q_INVOKABLE void startReplay(bool withMic = false);
    Q_INVOKABLE void stopReplay();
    Q_INVOKABLE void toggleReplay();
    Q_INVOKABLE void saveReplay(int seconds = 0);

    Q_INVOKABLE void toggleMic();
    Q_INVOKABLE void openRecordingsFolder();
    Q_INVOKABLE void openReplaysFolder();

signals:
    void recordingStateChanged();
    void replayStateChanged();
    void recordingSecondsChanged();
    void micEnabledChanged();
    void fpsChanged();
    void replaySecondsChanged();
    void screenNameChanged();
    void recordingsDirChanged();
    void replaysDirChanged();
    void lastSavedFileChanged();
    void notificationRequested(const QString &title, const QString &message);

private slots:
    void onTick();
    void pollExternalState();

private:
    void ensureDirectories();
    QString stateDir() const;
    QString recordPidFilePath() const;
    QString replayPidFilePath() const;
    qint64 readPidFromFile(const QString &path) const;
    void writePidToFile(const QString &path, qint64 pid) const;
    void removePidFile(const QString &path) const;
    bool isProcessRunning(qint64 pid) const;
    QString detectDefaultScreen() const;
    QString resolveAudioSource(bool withMic) const;

    static ScreenRecorderController *s_instance;

    bool m_isRecording = false;
    bool m_isPaused = false;
    bool m_isReplayActive = false;
    int m_recordingSeconds = 0;
    bool m_micEnabled = false;
    int m_fps = 60;
    int m_replaySeconds = 60;
    int m_replayBitrate = 20000;
    QString m_screenName;
    QString m_recordingsDir;
    QString m_replaysDir;
    QString m_lastSavedFile;
    QString m_currentRecordingFile;
    mutable QString m_cachedDetectedScreen;

    qint64 m_recordPid = 0;
    qint64 m_replayPid = 0;

    QTimer m_tickTimer;
    QTimer m_pollTimer;
};
