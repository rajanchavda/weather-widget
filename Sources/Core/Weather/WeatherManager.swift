import Foundation
import Combine
import Network

@MainActor
class WeatherManager: ObservableObject {
    @Published var currentTemp: Double = 0.0
    @Published var weatherCode: Int = 0
    @Published var hourlyTemps: [Double] = []
    @Published var hourlyCodes: [Int] = []
    @Published var hourlyTimes: [String] = []
    @Published var hourlyPrecipitation: [Double] = []
    @Published var cityName: String = "Detecting..."
    @Published var isNight: Bool = false
    @Published var isFetching: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var hasData: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isPaused: Bool = false
    @Published var aqiValue: Double? = nil
    @Published var aqiLabel: String = ""

    @Published var savedLocations: [SavedLocation] = []
    var currentHourIndex: Int = -1
    /// UTC offset for the active forecast location (from Open-Meteo `timezone=auto`).
    var forecastUtcOffsetSeconds: Int? = nil
    @Published var activeLocationId: UUID? = nil

    private let activeIdKey = "WeatherOverlay.activeLocationId"
    private let hourlyWindowSize = 12

    private var timer: AnyCancellable?
    private var fetchGeneration: Int = 0
    private let pathMonitor = NWPathMonitor()
    nonisolated(unsafe) private var lastPathStatus: NWPath.Status = .satisfied

    var manualLocation: ManualLocation? {
        get { ManualLocation.load() }
        set { ManualLocation.save(newValue) }
    }

    var currentPrecipitation: Double? {
        guard currentHourIndex >= 0,
              currentHourIndex < hourlyPrecipitation.count else { return nil }
        return hourlyPrecipitation[currentHourIndex]
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 5.0
            config.timeoutIntervalForResource = 5.0
            return URLSession(configuration: config)
        }()
        loadSavedLocations()
    }

#if swift(>=6.0)
    nonisolated deinit {
        pathMonitor.cancel()
    }
#else
    deinit {
        pathMonitor.cancel()
    }
#endif

    func start() {
        isPaused = false
        loadSavedLocations()
        fetchWeather()
        startTimer()
        setupNetworkMonitoring()
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        print("[WeatherManager] Paused — cancelling timer.")
        timer?.cancel()
        timer = nil
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        print("[WeatherManager] Resumed — restarting timer and refreshing.")
        fetchWeather()
        startTimer()
    }

    private func startTimer() {
        timer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchWeather()
            }
    }

    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let status = path.status
            let previous = self.lastPathStatus
            self.lastPathStatus = status
            print("[WeatherManager] Network path status updated: \(status). Previous status: \(previous)")
            if status == .satisfied && previous != .satisfied {
                print("[WeatherManager] Network connection restored. Triggering instant fetch...")
                Task { @MainActor [weak self] in
                    self?.fetchWeather()
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .background))
    }

    // MARK: - Saved Location Management

    private func loadSavedLocations() {
        savedLocations = SavedLocation.loadAll()
        if let idString = UserDefaults.standard.string(forKey: activeIdKey),
           let id = UUID(uuidString: idString) {
            activeLocationId = id
        }
        migrateLegacyManualLocation()
        if let activeId = activeLocationId,
           savedLocations.contains(where: { $0.id == activeId }) {
            syncManualLocationFromActiveId()
        } else {
            activeLocationId = nil
        }
    }

    private func migrateLegacyManualLocation() {
        guard savedLocations.isEmpty else { return }
        guard let legacy = ManualLocation.load() else { return }
        let saved = SavedLocation(
            id: UUID(),
            name: legacy.name,
            latitude: legacy.latitude,
            longitude: legacy.longitude
        )
        savedLocations = [saved]
        activeLocationId = saved.id
        saveSavedLocations()
        print("[WeatherManager] Migrated legacy manual location: \(legacy.name)")
    }

    private func saveSavedLocations() {
        SavedLocation.saveAll(savedLocations)
        if let id = activeLocationId {
            UserDefaults.standard.set(id.uuidString, forKey: activeIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeIdKey)
        }
    }

    private func syncManualLocationFromActiveId() {
        guard let id = activeLocationId,
              let location = savedLocations.first(where: { $0.id == id }) else {
            manualLocation = nil
            return
        }
        manualLocation = ManualLocation(
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    func switchToLocation(id: UUID?) {
        guard let id = id, savedLocations.contains(where: { $0.id == id }) else {
            switchToAutoLocation()
            return
        }
        activeLocationId = id
        syncManualLocationFromActiveId()
        saveSavedLocations()
        fetchWeather()
    }

    func switchToAutoLocation() {
        activeLocationId = nil
        manualLocation = nil
        saveSavedLocations()
        fetchWeather()
    }

    func addSavedLocation(_ location: SavedLocation) {
        if savedLocations.contains(where: { $0.id == location.id }) { return }
        if savedLocations.contains(where: { $0.name == location.name &&
            abs($0.latitude - location.latitude) < 0.01 &&
            abs($0.longitude - location.longitude) < 0.01 }) { return }
        savedLocations.append(location)
        activeLocationId = location.id
        syncManualLocationFromActiveId()
        saveSavedLocations()
        fetchWeather()
    }

    func removeSavedLocation(id: UUID) {
        savedLocations.removeAll { $0.id == id }
        if activeLocationId == id {
            activeLocationId = nil
            manualLocation = nil
        }
        saveSavedLocations()
        fetchWeather()
    }

    func saveCurrentAsSavedLocation() {
        let locName = cityName
        let lat: Double
        let lon: Double
        if let manual = manualLocation {
            lat = manual.latitude
            lon = manual.longitude
        } else {
            return
        }
        let newLocation = SavedLocation(
            id: UUID(),
            name: locName,
            latitude: lat,
            longitude: lon
        )
        addSavedLocation(newLocation)
    }

    func fetchWeather() {
        if isPaused {
            print("[WeatherManager] fetchWeather() skipped — paused.")
            return
        }
        print("[WeatherManager] fetchWeather() invoked. isFetching=\(isFetching)")
        fetchGeneration &+= 1
        let generation = fetchGeneration
        isFetching = true
        errorMessage = nil

        print("[WeatherManager] Spawning background fetch task (gen=\(generation))...")
        Task {
            print("[WeatherManager] Background fetch task started.")
            do {
                let lat: Double
                let lon: Double
                let city: String
                if let manual = self.manualLocation {
                    print("[WeatherManager] Using manual location: \(manual.name) (\(manual.latitude), \(manual.longitude))")
                    lat = manual.latitude
                    lon = manual.longitude
                    city = manual.name
                } else {
                    print("[WeatherManager] Fetching coordinates from IP geolocator...")
                    let location = try await fetchLocation()
                    lat = location.latitude
                    lon = location.longitude
                    city = location.city ?? "My Location"
                    print("[WeatherManager] Geolocation success: \(city) (\(lat), \(lon))")
                }

                print("[WeatherManager] Fetching weather forecast data...")
                let weather = try await fetchWeatherData(lat: lat, lon: lon)
                print("[WeatherManager] Weather data fetched. Temp=\(weather.current.temperature_2m)°C, WMO Code=\(weather.current.weather_code)")

                guard generation == self.fetchGeneration else {
                    print("[WeatherManager] Discarding stale success result (gen=\(generation), current=\(self.fetchGeneration))")
                    return
                }
                self.applyWeatherResponse(weather, cityName: city, useLocalNightFallback: false)
                self.isFetching = false
                print("[WeatherManager] fetchWeather() completed successfully.")

                do {
                    print("[WeatherManager] Fetching air quality data...")
                    let aqi = try await fetchAirQuality(lat: lat, lon: lon)
                    guard generation == self.fetchGeneration else {
                        print("[WeatherManager] Discarding stale AQI result (gen=\(generation), current=\(self.fetchGeneration))")
                        return
                    }
                    if let value = aqi.current.europeanAqi {
                        self.aqiValue = value
                        self.aqiLabel = AQICategory.from(europeanAqi: value).label
                    } else {
                        self.aqiValue = nil
                        self.aqiLabel = ""
                    }
                    print("[WeatherManager] Air quality fetched: AQI=\(self.aqiValue ?? -1) \(self.aqiLabel)")
                } catch {
                    print("[WeatherManager] AQI fetch failed (non-fatal): \(error.localizedDescription)")
                    guard generation == self.fetchGeneration else {
                        print("[WeatherManager] Discarding stale AQI error (gen=\(generation), current=\(self.fetchGeneration))")
                        return
                    }
                    self.aqiValue = nil
                    self.aqiLabel = ""
                }
            } catch {
                print("[WeatherManager] Primary fetch error: \(error.localizedDescription)")
                let primaryErrStr = error.localizedDescription

                do {
                    print("[WeatherManager] Initiating fallback fetch (London: 51.5074, -0.1278)...")
                    let weather = try await fetchWeatherData(lat: 51.5074, lon: -0.1278)

                    guard generation == self.fetchGeneration else {
                        print("[WeatherManager] Discarding stale fallback result (gen=\(generation), current=\(self.fetchGeneration))")
                        return
                    }
                    self.applyWeatherResponse(weather, cityName: "London (Fallback)", useLocalNightFallback: true)
                    self.errorMessage = nil
                    self.isFetching = false
                    print("[WeatherManager] Fallback completed.")

                    do {
                        print("[WeatherManager] Fetching air quality data (fallback)...")
                        let aqi = try await fetchAirQuality(lat: 51.5074, lon: -0.1278)
                        guard generation == self.fetchGeneration else {
                            print("[WeatherManager] Discarding stale AQI result (gen=\(generation), current=\(self.fetchGeneration))")
                            return
                        }
                        if let value = aqi.current.europeanAqi {
                            self.aqiValue = value
                            self.aqiLabel = AQICategory.from(europeanAqi: value).label
                        } else {
                            self.aqiValue = nil
                            self.aqiLabel = ""
                        }
                        print("[WeatherManager] Air quality fetched (fallback): AQI=\(self.aqiValue ?? -1) \(self.aqiLabel)")
                    } catch {
                        print("[WeatherManager] AQI fetch failed (fallback, non-fatal): \(error.localizedDescription)")
                        guard generation == self.fetchGeneration else {
                            print("[WeatherManager] Discarding stale AQI error (gen=\(generation), current=\(self.fetchGeneration))")
                            return
                        }
                        self.aqiValue = nil
                        self.aqiLabel = ""
                    }
                } catch {
                    print("[WeatherManager] Fallback weather fetch also failed: \(error.localizedDescription)")
                    guard generation == self.fetchGeneration else {
                        print("[WeatherManager] Discarding stale error (gen=\(generation), current=\(self.fetchGeneration))")
                        return
                    }
                    self.isNight = computeIsNightLocally()
                    self.errorMessage = "Fetch Failed: \(primaryErrStr) (Fallback failed: \(error.localizedDescription))"
                    self.isFetching = false
                }
            }
        }
    }

    private func fetchLocation() async throws -> GeoResponse {
        do {
            guard let url = URL(string: "https://freeipapi.com/api/json") else {
                throw URLError(.badURL)
            }
            let (data, _) = try await session.data(from: url)
            let freeGeo = try JSONDecoder().decode(FreeGeoResponse.self, from: data)
            return GeoResponse(latitude: freeGeo.latitude, longitude: freeGeo.longitude, city: freeGeo.cityName)
        } catch {
            print("Primary geolocator failed: \(error.localizedDescription). Trying secondary...")

            guard let url = URL(string: "https://ipapi.co/json/") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("WeatherOverlayApp/1.0", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await session.data(for: request)
            return try JSONDecoder().decode(GeoResponse.self, from: data)
        }
    }

    nonisolated func searchCity(_ query: String) async throws -> ManualLocation? {
        guard var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        print("[WeatherManager] searchCity GET \(url.absoluteString)")

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            print("[WeatherManager] searchCity HTTP \(http.statusCode), bytes=\(data.count)")
        }
        let resp = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        print("[WeatherManager] searchCity decoded results count=\(resp.results?.count ?? 0)")
        guard let first = resp.results?.first else { return nil }

        let displayName: String = {
            if let admin = first.admin1, !admin.isEmpty, admin != first.name {
                return "\(first.name), \(admin)"
            }
            if let country = first.country, !country.isEmpty {
                return "\(first.name), \(country)"
            }
            return first.name
        }()
        return ManualLocation(name: displayName, latitude: first.latitude, longitude: first.longitude)
    }

    private func applyWeatherResponse(_ weather: WeatherResponse, cityName: String, useLocalNightFallback: Bool) {
        let offset = weather.utc_offset_seconds
        self.forecastUtcOffsetSeconds = offset
        let window = sliceHourlyWindow(from: weather, utcOffsetSeconds: offset)

        self.currentTemp = weather.current.temperature_2m
        self.weatherCode = weather.current.weather_code
        self.hourlyTemps = window.temps
        self.hourlyCodes = window.codes
        self.hourlyTimes = window.times
        self.hourlyPrecipitation = window.precipitation
        // Window is already aligned to "now", so current hour is index 0 when data exists.
        self.currentHourIndex = window.times.isEmpty ? -1 : 0
        self.cityName = cityName
        if useLocalNightFallback {
            self.isNight = computeIsNightLocally(utcOffsetSeconds: offset)
        } else {
            self.isNight = weather.current.is_day == 0
        }
        self.lastUpdated = Date()
        self.hasData = true
    }

    /// Takes the next `hourlyWindowSize` hours starting at the location's current hour.
    private func sliceHourlyWindow(
        from weather: WeatherResponse,
        utcOffsetSeconds: Int?
    ) -> (temps: [Double], codes: [Int], times: [String], precipitation: [Double]) {
        let times = weather.hourly.time
        let temps = weather.hourly.temperature_2m
        let codes = weather.hourly.weather_code
        let precip = weather.hourly.precipitation ?? Array(repeating: 0.0, count: times.count)

        let start = computeCurrentHourIndex(from: times, utcOffsetSeconds: utcOffsetSeconds)
        let resolvedStart: Int
        if start >= 0 {
            resolvedStart = start
        } else {
            // If "now" isn't string-matched (clock skew / missing offset), keep the
            // in-progress hour: any bucket whose end is still in the future.
            resolvedStart = times.firstIndex(where: { timeStr in
                guard let date = parseHourlyTime(timeStr, utcOffsetSeconds: utcOffsetSeconds) else { return false }
                return date.addingTimeInterval(3600) > Date()
            }) ?? max(0, times.count - hourlyWindowSize)
        }

        let end = min(resolvedStart + hourlyWindowSize, times.count)
        guard resolvedStart < end else {
            return ([], [], [], [])
        }

        return (
            safeSlice(temps, from: resolvedStart, to: end),
            safeSlice(codes, from: resolvedStart, to: end),
            safeSlice(times, from: resolvedStart, to: end),
            safeSlice(precip, from: resolvedStart, to: end)
        )
    }

    private func safeSlice<T>(_ array: [T], from start: Int, to end: Int) -> [T] {
        let lower = min(max(start, 0), array.count)
        let upper = min(max(end, lower), array.count)
        return Array(array[lower..<upper])
    }

    private func parseHourlyTime(_ timeStr: String, utcOffsetSeconds: Int?) -> Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = timeZoneForForecast(utcOffsetSeconds: utcOffsetSeconds)
        if let date = df.date(from: timeStr) { return date }

        df.dateFormat = "yyyy-MM-dd'T'HH:00"
        return df.date(from: timeStr)
    }

    private func timeZoneForForecast(utcOffsetSeconds: Int?) -> TimeZone {
        if let offset = utcOffsetSeconds, let tz = TimeZone(secondsFromGMT: offset) {
            return tz
        }
        return TimeZone.current
    }

    private func computeCurrentHourIndex(from times: [String], utcOffsetSeconds: Int? = nil) -> Int {
        guard !times.isEmpty else { return -1 }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:00"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = timeZoneForForecast(utcOffsetSeconds: utcOffsetSeconds ?? forecastUtcOffsetSeconds)
        let currentHourStr = df.string(from: Date())
        for (i, timeStr) in times.enumerated() {
            if timeStr == currentHourStr || timeStr.hasPrefix(currentHourStr) {
                return i
            }
        }
        return -1
    }

    private func computeIsNightLocally(utcOffsetSeconds: Int? = nil) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZoneForForecast(utcOffsetSeconds: utcOffsetSeconds ?? forecastUtcOffsetSeconds)
        let hour = calendar.component(.hour, from: Date())
        return hour < 6 || hour >= 20
    }

    private func fetchWeatherData(lat: Double, lon: Double) async throws -> WeatherResponse {
        let posixLocale = Locale(identifier: "en_US_POSIX")
        let latStr = String(format: "%.6f", locale: posixLocale, lat)
        let lonStr = String(format: "%.6f", locale: posixLocale, lon)

        // forecast_days=2 so late-day requests still have a full 12-hour forward window.
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latStr)&longitude=\(lonStr)&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,precipitation&forecast_days=2&timezone=auto"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(WeatherResponse.self, from: data)
    }

    private func fetchAirQuality(lat: Double, lon: Double) async throws -> AirQualityResponse {
        let posixLocale = Locale(identifier: "en_US_POSIX")
        let latStr = String(format: "%.6f", locale: posixLocale, lat)
        let lonStr = String(format: "%.6f", locale: posixLocale, lon)

        let urlString = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(latStr)&longitude=\(lonStr)&current=european_aqi"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(AirQualityResponse.self, from: data)
    }
}
