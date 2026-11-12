import Foundation

/// Cálculo de salida y puesta de sol (algoritmo de la NOAA), para el modo nocturno automático.
public enum Solar {
    /// Elevación del sol sobre el horizonte, en grados.
    public static func elevation(at date: Date, coordinate: Coordinate) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525

        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let m = Geo.rad(meanAnomaly)
        let center = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t) + sin(3 * m) * 0.000289
        let trueLongitude = meanLongitude + center
        let omega = Geo.rad(125.04 - 1934.136 * t)
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(omega)
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = Geo.rad(meanObliquity + 0.00256 * cos(omega))
        let declination = asin(sin(obliquity) * sin(Geo.rad(apparentLongitude)))

        let y = tan(obliquity / 2) * tan(obliquity / 2)
        let l0 = Geo.rad(meanLongitude)
        let equationOfTime = 4 * Geo.deg(
            y * sin(2 * l0) - 2 * eccentricity * sin(m) + 4 * eccentricity * y * sin(m) * cos(2 * l0)
                - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m))

        let minutesUTC = (date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400)) / 60
        var solarMinutes = (minutesUTC + equationOfTime + 4 * coordinate.longitude).truncatingRemainder(dividingBy: 1440)
        if solarMinutes < 0 { solarMinutes += 1440 }
        let hourAngle = Geo.rad(solarMinutes / 4 - 180)

        let latitude = Geo.rad(coordinate.latitude)
        let cosZenith = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)
        return 90 - Geo.deg(acos(max(-1, min(1, cosZenith))))
    }

    /// Noche a efectos de interfaz: sol por debajo de −4° (se adelanta un poco al crepúsculo civil).
    public static func isNight(at date: Date, coordinate: Coordinate) -> Bool {
        elevation(at: date, coordinate: coordinate) < -4
    }
}
