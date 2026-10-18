import Foundation
import Combine
import Network
import os

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
    /// True while the last refresh failed and the previous good data is still being shown.
    @Published var isStale: Bool = false
    @Published var aqiValue: Double? = nil
    @Published var aqiLabel: String = ""

    @Published var savedLocations: [SavedLocation] = []
    var currentHourIndex: Int = -1
    /// UTC offset for the active forecast location (from Open-Meteo `timezone=auto`).
    var forecastUtcOffsetSeconds: Int? = nil
    @Published var activeLocationId: UUID? = nil

    private let activeIdKey = "WeatherOverlay.activeLocationId"
    /// Single-city override from before multi-city support. Read once by the migration, then removed.
    private let legacyManualLocationKey = "WeatherOverlay.manualLocation"
    private let hourlyWindowSize = 12
    /// How long the last good data is kept through failed refreshes before it is dropped.
    static let maxStaleAge: TimeInterval = 3 * 3600
    /// Identifies the location the current data was fetched for.
    private var dataSourceKey: String?

    /// How long a geo-IP result is reused before it is looked up again.
    static let geoLocationCacheLifetime: TimeInterval = 3600
    /// How many geocoding matches the Add Location picker offers.
    nonisolated static let citySearchLimit = 5
    /// Clock for the geo-IP cache, replaceable so tests can age an entry without sleeping.
    var now: () -> Date = { Date() }

    private struct CachedGeoLocation {
        let location: GeoResponse
        let fetchedAt: Date
        /// Set when the network may have changed: look up again, but keep this as a fallback.
        var needsRevalidation: Bool
    }
    /// Last successful geo-IP result. In memory only, so a relaunch always looks up afresh.
    private var cachedGeoLocation: CachedGeoLocation?
    /// Bumped on every invalidation, so a lookup that was already in flight is not stored as fresh.
    private var geoCacheEpoch: Int = 0
    /// The path monitor reports the current path once when it starts; that is not a change.
    private var hasReceivedInitialNetworkPath = false

    private var timer: AnyCancellable?
    private var fetchGeneration: Int = 0
    private let pathMonitor = NWPathMonitor()
    nonisolated(unsafe) private var lastPathStatus: NWPath.Status = .satisfied

    /// The selected saved city, or nil when the location is automatic (IP-based).
    var activeLocation: SavedLocation? {
        guard let id = activeLocationId else { return nil }
        return savedLocations.first { $0.id == id }
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
            config.timeoutIntervalForRequest = 15.0
            config.timeoutIntervalForResource = 30.0
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
        Log.weather.info("Paused — cancelling timer.")
        timer?.cancel()
        timer = nil
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        Log.weather.info("Resumed — restarting timer and refreshing.")
        // The machine may have moved while it was asleep or locked.
        invalidateGeoLocationCache()
        fetchWeather()
        startTimer()
    }

    /// Refreshes at the user's explicit request, looking the location up again instead of
    /// trusting the cached geo-IP result.
    func forceRefresh() {
        invalidateGeoLocationCache()
        fetchWeather()
    }

    /// Makes the next auto-location refresh look the location up again. The held result is
    /// kept, marked for revalidation, so it can still stand in if that lookup fails.
    /// Does not start a fetch.
    func invalidateGeoLocationCache() {
        geoCacheEpoch &+= 1
        cachedGeoLocation?.needsRevalidation = true
    }

    /// Any path update after the monitor's initial report can mean a new public IP (VPN
    /// toggle, Wi-Fi change) even while the path stays satisfied.
    func networkPathDidUpdate(connectionRestored: Bool) {
        if hasReceivedInitialNetworkPath {
            invalidateGeoLocationCache()
        }
        hasReceivedInitialNetworkPath = true
        if connectionRestored {
            fetchWeather()
        }
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
            Log.weather.info("Network path status updated: \(String(describing: status), privacy: .public). Previous status: \(String(describing: previous), privacy: .public)")
            let restored = status == .satisfied && previous != .satisfied
            if restored {
                Log.weather.notice("Network connection restored. Triggering instant fetch...")
            }
            // This handler runs off the main thread and the geo-IP cache is main-actor state,
            // so hop there. One task keeps the invalidation ahead of the reconnect fetch.
            Task { @MainActor [weak self] in
                self?.networkPathDidUpdate(connectionRestored: restored)
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
        if activeLocation == nil {
            activeLocationId = nil
        }
    }

    private struct LegacyManualLocation: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    /// Carries the single city of a pre-multi-city install over as the active saved location.
    private func migrateLegacyManualLocation() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: legacyManualLocationKey) != nil else { return }
        // Removed whatever happens below, and only after the migrated city is saved, so the
        // migration can never run twice or bring back a city the user has since removed.
        defer { defaults.removeObject(forKey: legacyManualLocationKey) }

        // With saved locations present the key is only the mirror later versions kept writing.
        guard savedLocations.isEmpty,
              let data = defaults.data(forKey: legacyManualLocationKey),
              let legacy = try? JSONDecoder().decode(LegacyManualLocation.self, from: data) else { return }
        let saved = SavedLocation(
            id: UUID(),
            name: legacy.name,
            latitude: legacy.latitude,
            longitude: legacy.longitude
        )
        savedLocations = [saved]
        activeLocationId = saved.id
        saveSavedLocations()
        Log.weather.notice("Migrated legacy manual location: \(legacy.name, privacy: .public)")
    }

    private func saveSavedLocations() {
        SavedLocation.saveAll(savedLocations)
        if let id = activeLocationId {
            UserDefaults.standard.set(id.uuidString, forKey: activeIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeIdKey)
        }
    }

    func switchToLocation(id: UUID?) {
        guard let id = id, savedLocations.contains(where: { $0.id == id }) else {
            switchToAutoLocation()
            return
        }
        activeLocationId = id
        saveSavedLocations()
        fetchWeather()
    }

    func switchToAutoLocation() {
        activeLocationId = nil
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
        saveSavedLocations()
        fetchWeather()
    }

    func removeSavedLocation(id: UUID) {
        savedLocations.removeAll { $0.id == id }
        if activeLocationId == id {
            activeLocationId = nil
        }
        saveSavedLocations()
        fetchWeather()
    }

    func fetchWeather() {
        if isPaused {
            Log.weather.debug("fetchWeather() skipped — paused.")
            return
        }
        Log.weather.debug("fetchWeather() invoked. isFetching=\(self.isFetching, privacy: .public)")
        fetchGeneration &+= 1
        let generation = fetchGeneration
        isFetching = true
        errorMessage = nil

        Log.weather.debug("Spawning background fetch task (gen=\(generation, privacy: .public))...")
        Task {
            let saved = self.activeLocation
            let sourceKey = saved.map { "manual:\($0.latitude),\($0.longitude)" } ?? "auto"
            do {
                let lat: Double
                let lon: Double
                let city: String
                if let saved {
                    Log.weather.info("Using saved location: \(saved.name, privacy: .public) (\(saved.latitude, privacy: .private), \(saved.longitude, privacy: .private))")
                    lat = saved.latitude
                    lon = saved.longitude
                    city = saved.name
                } else {
                    let location = try await autoLocation(generation: generation)
                    lat = location.latitude
                    lon = location.longitude
                    city = location.city ?? "My Location"
                    Log.weather.info("Geolocation success: \(city, privacy: .public) (\(lat, privacy: .private), \(lon, privacy: .private))")
                }

                Log.weather.debug("Fetching weather forecast data...")
                let weather = try await fetchWeatherData(lat: lat, lon: lon)
                Log.weather.info("Weather data fetched. Temp=\(weather.current.temperature_2m, format: .fixed(precision: 1), privacy: .public)°C, WMO Code=\(weather.current.weather_code, privacy: .public)")

                guard generation == self.fetchGeneration else {
                    Log.weather.debug("Discarding stale success result (gen=\(generation, privacy: .public), current=\(self.fetchGeneration, privacy: .public))")
                    return
                }
                self.applyWeatherResponse(weather, cityName: city)
                self.dataSourceKey = sourceKey
                self.isFetching = false
                Log.weather.debug("fetchWeather() completed successfully.")

                do {
                    Log.weather.debug("Fetching air quality data...")
                    let aqi = try await fetchAirQuality(lat: lat, lon: lon)
                    guard generation == self.fetchGeneration else {
                        Log.weather.debug("Discarding stale AQI result (gen=\(generation, privacy: .public), current=\(self.fetchGeneration, privacy: .public))")
                        return
                    }
                    if let value = aqi.current.europeanAqi {
                        self.aqiValue = value
                        self.aqiLabel = AQICategory.from(europeanAqi: value).label
                    } else {
                        self.aqiValue = nil
                        self.aqiLabel = ""
                    }
                    Log.weather.info("Air quality fetched: AQI=\(self.aqiValue ?? -1, format: .fixed(precision: 0), privacy: .public) \(self.aqiLabel, privacy: .public)")
                } catch {
                    Log.weather.error("AQI fetch failed (non-fatal): \(error.localizedDescription, privacy: .public)")
                    guard generation == self.fetchGeneration else {
                        Log.weather.debug("Discarding stale AQI error (gen=\(generation, privacy: .public), current=\(self.fetchGeneration, privacy: .public))")
                        return
                    }
                    self.aqiValue = nil
                    self.aqiLabel = ""
                }
            } catch {
                Log.weather.error("Fetch error: \(error.localizedDescription, privacy: .public)")
                guard generation == self.fetchGeneration else {
                    Log.weather.debug("Discarding stale error (gen=\(generation, privacy: .public), current=\(self.fetchGeneration, privacy: .public))")
                    return
                }
                self.handleFetchFailure(error, sourceKey: sourceKey)
            }
        }
    }

    /// Keeps the last good data on screen, marked stale, when it is recent and for the
    /// same location. Otherwise there is nothing truthful to show, so report the error.
    private func handleFetchFailure(_ error: Error, sourceKey: String) {
        let isRecent = lastUpdated.map { Date().timeIntervalSince($0) < Self.maxStaleAge } ?? false
        if hasData && dataSourceKey == sourceKey && isRecent {
            Log.weather.notice("Keeping last good data as stale.")
            isStale = true
        } else {
            hasData = false
            isStale = false
            dataSourceKey = nil
            hourlyTemps = []
            hourlyCodes = []
            hourlyTimes = []
            hourlyPrecipitation = []
            currentHourIndex = -1
            aqiValue = nil
            aqiLabel = ""
            isNight = computeIsNightLocally()
            errorMessage = "Fetch Failed: \(error.localizedDescription)"
        }
        isFetching = false
    }

    /// Location for an auto (IP-based) refresh: the cached geo-IP result while it is fresh,
    /// otherwise a new lookup. If the lookup fails, the last held result is used rather
    /// than failing the refresh, even when it is expired or marked for revalidation.
    private func autoLocation(generation: Int) async throws -> GeoResponse {
        if let cached = cachedGeoLocation, !cached.needsRevalidation {
            let age = now().timeIntervalSince(cached.fetchedAt)
            if age >= 0 && age < Self.geoLocationCacheLifetime {
                Log.weather.debug("Using cached geo-IP location (age=\(Int(age), privacy: .public)s).")
                return cached.location
            }
        }

        Log.weather.debug("Fetching coordinates from IP geolocator...")
        let epoch = geoCacheEpoch
        do {
            let location = try await fetchLocation()
            // A superseded fetch never writes the cache, so an older lookup cannot replace
            // the result of a newer one. If the cache was invalidated while this lookup was
            // in flight, the answer may describe the old network: use it for this refresh
            // but leave it marked so the next one looks up again.
            if generation == fetchGeneration {
                cachedGeoLocation = CachedGeoLocation(
                    location: location,
                    fetchedAt: now(),
                    needsRevalidation: epoch != geoCacheEpoch
                )
            }
            return location
        } catch {
            guard let held = cachedGeoLocation else { throw error }
            Log.weather.error("Geo-IP lookup failed: \(error.localizedDescription, privacy: .public). Using last known location.")
            return held.location
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
            Log.weather.error("Primary geolocator failed: \(error.localizedDescription, privacy: .public). Trying secondary...")

            guard let url = URL(string: "https://ipapi.co/json/") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("WeatherOverlayApp/1.0", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await session.data(for: request)
            return try JSONDecoder().decode(GeoResponse.self, from: data)
        }
    }

    nonisolated func searchCities(_ query: String) async throws -> [CityMatch] {
        guard var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: String(Self.citySearchLimit)),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        Log.weather.debug("searchCities GET \(url.absoluteString, privacy: .private)")

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            Log.weather.debug("searchCities HTTP \(http.statusCode, privacy: .public), bytes=\(data.count, privacy: .public)")
        }
        let resp = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        Log.weather.debug("searchCities decoded results count=\(resp.results?.count ?? 0, privacy: .public)")

        return (resp.results ?? []).prefix(Self.citySearchLimit).map { result in
            let admin = result.admin1.flatMap { $0.isEmpty || $0 == result.name ? nil : $0 }
            let country = result.country.flatMap { $0.isEmpty ? nil : $0 }
            let name = [result.name, admin ?? country].compactMap { $0 }.joined(separator: ", ")
            let pickerTitle = [result.name, admin, country].compactMap { $0 }.joined(separator: ", ")
            let location = SavedLocation(id: UUID(), name: name, latitude: result.latitude, longitude: result.longitude)
            return CityMatch(location: location, pickerTitle: pickerTitle)
        }
    }

    private func applyWeatherResponse(_ weather: WeatherResponse, cityName: String) {
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
        self.isNight = weather.current.is_day == 0
        self.lastUpdated = Date()
        self.isStale = false
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
