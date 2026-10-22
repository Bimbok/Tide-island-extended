#include "BatteryStatusUtils.h"

#include <QtTest>

class BatteryStatusUtilsTests : public QObject
{
    Q_OBJECT

private slots:
    void reportsDischargingWhenAdapterIsOffline()
    {
        QCOMPARE(BatteryStatusUtils::fallbackStatusFromAcOnline(QStringLiteral("0")),
                 QStringLiteral("Discharging"));
    }

    void doesNotAssumeChargingWhenAdapterIsOnline()
    {
        QCOMPARE(BatteryStatusUtils::fallbackStatusFromAcOnline(QStringLiteral("1")),
                 QStringLiteral("Unknown"));
    }

    void preservesUnknownForInvalidInput()
    {
        QCOMPARE(BatteryStatusUtils::fallbackStatusFromAcOnline(QString()),
                 QStringLiteral("Unknown"));
        QCOMPARE(BatteryStatusUtils::fallbackStatusFromAcOnline(QStringLiteral("not-a-number")),
                 QStringLiteral("Unknown"));
    }

    void trimsSysfsWhitespace()
    {
        QCOMPARE(BatteryStatusUtils::fallbackStatusFromAcOnline(QStringLiteral(" 0\n")),
                 QStringLiteral("Discharging"));
    }
};

QTEST_GUILESS_MAIN(BatteryStatusUtilsTests)
#include "battery_status_utils_tests.moc"
