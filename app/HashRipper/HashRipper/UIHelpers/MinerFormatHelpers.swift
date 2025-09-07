//
//  MinerFormatHelpers.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import Foundation

let suffixes = ["H/s", "KH/s", "MH/s", "GH/s", "TH/s", "PH/s", "EH/s"]

func formatMinerHashRate(rawRateValue: Double) -> (rateString: String, rateSuffix: String, rateValue: Double) {
    if rawRateValue == 0 {
        return ("0",suffixes[3], 0.0)
    }

    let rate = rawRateValue * 1000000000

    // Determine the “power of 1 000” to scale by.
    let power = max(0, Int(floor(log10(rate) / 3.0)))

    // Apply the scaling factor.
    let scaledValue = rate / pow(1000.0, Double(power))

    let suffix = suffixes[power];
    var decimals = 0
    if (scaledValue < 10) {
        decimals = 2
    } else if (scaledValue < 100) {
        decimals = 1
    }

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = decimals
    formatter.minimumFractionDigits = decimals
    let stringValue = formatter.string(from: NSNumber(value: scaledValue))!
    return (stringValue, suffix, scaledValue)
//    return (stringValue, suffix, formatter.number(from: stringValue)!.doubleValue)
//    return "\(String(format: "%.\(decimals)f", scaledValue)) \(suffix)"
}

func formatMinerTempValue(rawTempValue: Double?) -> String {
    guard case let .some(rawTempValue) = rawTempValue else {
        return "N/A"
    }

    let measurement = Measurement(value: rawTempValue, unit: UnitTemperature.celsius)
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .providedUnit        // keep the unit you pass in
    formatter.numberFormatter.maximumFractionDigits = 1
    formatter.numberFormatter.minimumFractionDigits = 1
    formatter.numberFormatter.minimumIntegerDigits = 2
    return formatter.string(from: measurement)

//    return formatter.for
//    let numberFormatter = NumberFormatter()
//    numberFormatter.minimumFractionDigits = 1
//
//    return return "\(String(format: "%.1f", rawTempValue)) °C"
}
