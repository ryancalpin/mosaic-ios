import SwiftUI

@MainActor
public final class CurlWttrRenderer: OutputRenderer {
    public let id          = "misc.weather"
    public let displayName = "Weather"
    public let badgeLabel  = "WEATHER"
    public let priority    = RendererPriority.generic + 80

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let isWttr = cmd.contains("wttr.in") || cmd.contains("wttr")
        let looksLike = output.contains("°") && (output.contains("km/h") || output.contains("mph") || output.contains("°C") || output.contains("°F"))
        return isWttr && looksLike
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        // wttr.in ?format=j1 returns JSON — detect and parse
        if output.trimmingCharacters(in: .whitespaces).hasPrefix("{"),
           let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseJSON(json, command: command)
        }
        // ASCII art format — parse key values from text
        return parseASCII(output, command: command)
    }

    private func parseJSON(_ json: [String: Any], command: String) -> WttrData? {
        guard let currentCondition = (json["current_condition"] as? [[String: Any]])?.first else { return nil }
        let tempC     = currentCondition["temp_C"] as? String ?? "?"
        let tempF     = currentCondition["temp_F"] as? String ?? "?"
        let feelsLikeC = currentCondition["FeelsLikeC"] as? String ?? ""
        let desc      = (currentCondition["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String ?? "Unknown"
        let humidity  = currentCondition["humidity"] as? String ?? "?"
        let windKmph  = currentCondition["windspeedKmph"] as? String ?? "?"
        let windDir   = currentCondition["winddir16Point"] as? String ?? ""
        let uvIndex   = currentCondition["uvIndex"] as? String ?? "?"
        let visibility = currentCondition["visibility"] as? String ?? "?"

        let location: String
        if let nearest = (json["nearest_area"] as? [[String: Any]])?.first,
           let areaName = (nearest["areaName"] as? [[String: Any]])?.first?["value"] as? String,
           let country  = (nearest["country"] as? [[String: Any]])?.first?["value"] as? String {
            location = "\(areaName), \(country)"
        } else {
            location = command.components(separatedBy: "wttr.in/").last ?? "Unknown"
        }

        var forecasts: [WttrForecast] = []
        if let weather = json["weather"] as? [[String: Any]] {
            for day in weather.prefix(3) {
                let date       = day["date"] as? String ?? ""
                let maxTempC   = day["maxtempC"] as? String ?? "?"
                let minTempC   = day["mintempC"] as? String ?? "?"
                let hourlyDescs = (day["hourly"] as? [[String: Any]])?.compactMap {
                    ($0["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String
                } ?? []
                let summary = hourlyDescs.first ?? "—"
                forecasts.append(WttrForecast(date: date, maxC: maxTempC, minC: minTempC, description: summary))
            }
        }

        return WttrData(
            location:    location,
            tempC:       tempC,
            tempF:       tempF,
            feelsLikeC:  feelsLikeC,
            description: desc,
            humidity:    humidity + "%",
            windKmph:    windKmph + " km/h \(windDir)",
            uvIndex:     uvIndex,
            visibility:  visibility + " km",
            forecasts:   forecasts
        )
    }

    private func parseASCII(_ output: String, command: String) -> WttrData? {
        let lines = output.components(separatedBy: "\n")
        guard lines.count > 5 else { return nil }

        var tempC = ""; let desc = ""; var humidity = ""; var wind = ""; var location = ""

        let ansiRx = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*m"#)
        func clean(_ s: String) -> String {
            let ns = s as NSString
            return ansiRx?.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "") ?? s
        }

        for line in lines {
            let c = clean(line)
            if c.contains("°C") || c.contains("°F"), tempC.isEmpty {
                if let r = c.range(of: #"-?\d+°C"#, options: .regularExpression) {
                    tempC = String(c[r])
                }
            }
            if c.contains("km/h") && wind.isEmpty { wind = c.trimmingCharacters(in: .whitespaces) }
            if c.contains("Humidity") { humidity = c.trimmingCharacters(in: .whitespaces) }
            if location.isEmpty, c.contains(","), !c.contains("°") {
                location = c.trimmingCharacters(in: .whitespaces)
            }
        }

        guard !tempC.isEmpty else { return nil }
        return WttrData(
            location:    location.isEmpty ? "Unknown" : location,
            tempC:       tempC,
            tempF:       "",
            feelsLikeC:  "",
            description: desc.isEmpty ? "Current conditions" : desc,
            humidity:    humidity,
            windKmph:    wind,
            uvIndex:     "",
            visibility:  "",
            forecasts:   []
        )
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? WttrData else { return AnyView(EmptyView()) }
        return AnyView(WeatherView(data: data))
    }
}

public struct WttrData: RendererData {
    public let location:    String
    public let tempC:       String
    public let tempF:       String
    public let feelsLikeC:  String
    public let description: String
    public let humidity:    String
    public let windKmph:    String
    public let uvIndex:     String
    public let visibility:  String
    public let forecasts:   [WttrForecast]
}

public struct WttrForecast: Identifiable, Sendable {
    public let id          = UUID()
    public let date:        String
    public let maxC:        String
    public let minC:        String
    public let description: String
}

struct WeatherView: View {
    let data: WttrData

    private var tempNum: Double? { Double(data.tempC.replacingOccurrences(of: "°C", with: "").trimmingCharacters(in: .whitespaces)) }

    private var weatherIcon: String {
        let desc = data.description.lowercased()
        if desc.contains("sun") || desc.contains("clear") { return "sun.max.fill" }
        if desc.contains("cloud") && desc.contains("sun")  { return "cloud.sun.fill" }
        if desc.contains("cloud")                          { return "cloud.fill" }
        if desc.contains("rain") || desc.contains("drizzle") { return "cloud.rain.fill" }
        if desc.contains("snow") || desc.contains("sleet")   { return "cloud.snow.fill" }
        if desc.contains("thunder") || desc.contains("storm") { return "cloud.bolt.fill" }
        if desc.contains("fog") || desc.contains("mist")     { return "cloud.fog.fill" }
        return "cloud.fill"
    }

    private var tempColor: Color {
        guard let t = tempNum else { return Color(hex: "#D8E4F0") }
        if t < 0   { return Color(hex: "#4A9EFF") }
        if t < 15  { return Color(hex: "#00D4AA") }
        if t < 25  { return Color(hex: "#FFD060") }
        return Color(hex: "#FF4D6A")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: weatherIcon)
                    .font(.system(size: 36))
                    .foregroundColor(tempColor)
                    .symbolRenderingMode(.multicolor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(data.tempC)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(tempColor)
                        if !data.feelsLikeC.isEmpty {
                            Text("feels \(data.feelsLikeC)°")
                                .font(.custom("JetBrains Mono", size: 10))
                                .foregroundColor(Color(hex: "#3A4A58"))
                        }
                    }
                    Text(data.description)
                        .font(.custom("JetBrains Mono", size: 10))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color(hex: "#3A4A58"))
                        Text(data.location)
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#3A4A58"))
                    }
                }

                Spacer()

                Text("WEATHER")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !data.humidity.isEmpty || !data.windKmph.isEmpty || !data.uvIndex.isEmpty {
                Divider().overlay(Color(hex: "#1E1E26"))

                HStack(spacing: 0) {
                    if !data.humidity.isEmpty {
                        weatherStat(icon: "humidity.fill", label: "HUMIDITY", value: data.humidity)
                        Divider().overlay(Color(hex: "#1E1E26"))
                    }
                    if !data.windKmph.isEmpty {
                        weatherStat(icon: "wind", label: "WIND", value: data.windKmph)
                        Divider().overlay(Color(hex: "#1E1E26"))
                    }
                    if !data.visibility.isEmpty {
                        weatherStat(icon: "eye.fill", label: "VIS", value: data.visibility)
                    }
                }
                .frame(height: 56)
            }

            if !data.forecasts.isEmpty {
                Divider().overlay(Color(hex: "#1E1E26"))
                HStack(spacing: 0) {
                    ForEach(data.forecasts) { day in
                        VStack(spacing: 4) {
                            Text(shortDate(day.date))
                                .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                                .foregroundColor(Color(hex: "#3A4A58"))
                            Text("\(day.maxC)°")
                                .font(.custom("JetBrains Mono", size: 11).weight(.semibold))
                                .foregroundColor(Color(hex: "#FFD060"))
                            Text("\(day.minC)°")
                                .font(.custom("JetBrains Mono", size: 10))
                                .foregroundColor(Color(hex: "#4A9EFF"))
                            Text(day.description)
                                .font(.custom("JetBrains Mono", size: 8))
                                .foregroundColor(Color(hex: "#3A4A58"))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        if day.id != data.forecasts.last?.id {
                            Divider().overlay(Color(hex: "#1E1E26"))
                        }
                    }
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }

    @ViewBuilder
    private func weatherStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#3A4A58"))
            Text(value.prefix(12).description)
                .font(.custom("JetBrains Mono", size: 9).weight(.semibold))
                .foregroundColor(Color(hex: "#D8E4F0"))
                .lineLimit(1)
            Text(label)
                .font(.custom("JetBrains Mono", size: 7).weight(.bold))
                .foregroundColor(Color(hex: "#3A4A58"))
                .kerning(0.3)
        }
        .frame(maxWidth: .infinity)
    }

    private func shortDate(_ iso: String) -> String {
        // "2024-01-15" → "Mon 15"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: iso) else { return iso }
        df.dateFormat = "EEE d"
        return df.string(from: date)
    }
}
