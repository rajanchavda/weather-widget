import Foundation
import Combine
import Network

@MainActor
class WeatherManager: ObservableObject {
    @Published var currentTemp: Double = 0.0
    @Published var weatherCode: Int = 0
    @Published var hourlyTemps: [Double] = []
    @Published var hourlyCodes: [Int] = []
    @Published var cityName: String = "Detecting..."
    @Published var isNight: Bool = false
    @Published var isFetching: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var hasData: Bool = false
    @Published var errorMessage: String? = nil

    private var timer: AnyCancellable?
    private var fetchGeneration: Int = 0
    private let pathMonitor = NWPathMonitor()
    nonisolated(unsafe) private var lastPathStatus: NWPath.Status = .satisfied

    var manualLocation: ManualLocation? {
        get { ManualLocation.load() }
        set { ManualLocation.save(newValue) }
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 5.0
            config.timeoutIntervalForResource = 5.0
            return URLSession(configuration: config)
        }()
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
        fetchWeather()

        timer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchWeather()
            }

        setupNetworkMonitoring()
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

    func fetchWeather() {
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
                self.currentTemp = weather.current.temperature_2m
                self.weatherCode = weather.current.weather_code
                self.hourlyTemps = Array(weather.hourly.temperature_2m.prefix(12))
                self.hourlyCodes = Array(weather.hourly.weather_code.prefix(12))
                self.cityName = city
                self.isNight = weather.current.is_day == 0
                self.lastUpdated = Date()
                self.hasData = true
                self.isFetching = false
                print("[WeatherManager] fetchWeather() completed successfully.")
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
                    self.cityName = "London (Fallback)"
                    self.currentTemp = weather.current.temperature_2m
                    self.weatherCode = weather.current.weather_code
                    self.hourlyTemps = Array(weather.hourly.temperature_2m.prefix(12))
                    self.hourlyCodes = Array(weather.hourly.weather_code.prefix(12))
                    self.isNight = computeIsNightLocally()
                    self.lastUpdated = Date()
                    self.hasData = true
                    self.errorMessage = nil
                    self.isFetching = false
                    print("[WeatherManager] Fallback completed.")
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

    private func computeIsNightLocally() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 6 || hour >= 20
    }

    private func fetchWeatherData(lat: Double, lon: Double) async throws -> WeatherResponse {
        let posixLocale = Locale(identifier: "en_US_POSIX")
        let latStr = String(format: "%.6f", locale: posixLocale, lat)
        let lonStr = String(format: "%.6f", locale: posixLocale, lon)

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latStr)&longitude=\(lonStr)&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code&forecast_days=1"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(WeatherResponse.self, from: data)
    }
}
