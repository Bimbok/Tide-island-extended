#pragma once

#include <QString>

namespace BatteryStatusUtils {

// AC-online state tells us whether external power is connected, not whether the
// battery is actively charging. Only infer discharging when AC is explicitly
// offline; otherwise leave the status unknown until a battery-specific source
// (sysfs or UPower) can report it.
inline QString fallbackStatusFromAcOnline(const QString &onlineValue)
{
    bool ok = false;
    const int isOnline = onlineValue.trimmed().toInt(&ok);
    if (!ok || isOnline != 0)
        return QStringLiteral("Unknown");

    return QStringLiteral("Discharging");
}

} // namespace BatteryStatusUtils
