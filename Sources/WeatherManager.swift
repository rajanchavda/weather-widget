import Foundation
import Combine

class WeatherManager: ObservableObject {
    @Published var currentTemp: Double = 0.0
    @Published var weatherCode: Int = 0
    @Published var hourlyTemps: [Double] = []
    @Published var hourlyCodes: [Int] = []
    @Published var cityName: String = "Detecting..."
    @Published var isFetching: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var hasData: Bool = false
    @Published var errorMessage: String? = nil
    
    private var timer: AnyCancellable?
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 5.0
        return URLSession(configuration: config)
    }()
    
    init() {
        // No-op: Call start() after application has finished launching
    }
    
    func start() {
        // Start the initial fetch
        fetchWeather()
        
        // Setup timer to refresh every 5 minutes (300 seconds)
        timer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchWeather()
            }
    }
    
    func fetchWeather() {
        print("[WeatherManager] fetchWeather() invoked. isFetching=\(isFetching)")
        guard !isFetching else {
            print("[WeatherManager] Already fetching, skipping.")
            return
        }
        isFetching = true
        self.errorMessage = nil
        
        print("[WeatherManager] Spawning background fetch task...")
        Task {
            print("[WeatherManager] Background fetch task started.")
            do {
                // 1. Get Location coordinates via IP Geolocation
                print("[WeatherManager] Fetching coordinates from geolocator...")
                let location = try await fetchLocation()
                let lat = location.latitude
                let lon = location.longitude
                let city = location.city ?? "My Location"
                print("[WeatherManager] Geolocation success: \(city) (\(lat), \(lon))")
                
                // 2. Fetch Weather from Open-Meteo
                print("[WeatherManager] Fetching weather forecast data...")
                let weather = try await fetchWeatherData(lat: lat, lon: lon)
                print("[WeatherManager] Weather data fetched. Temp=\(weather.current.temperature_2m)°C, WMO Code=\(weather.current.weather_code)")
                
                // 3. Update published state on the Main Thread
                runOnMainThread { [weak self] in
                    guard let self = self else { return }
                    self.currentTemp = weather.current.temperature_2m
                    self.weatherCode = weather.current.weather_code
                    self.hourlyTemps = Array(weather.hourly.temperature_2m.prefix(12))
                    self.hourlyCodes = Array(weather.hourly.weather_code.prefix(12))
                    self.cityName = city
                    self.lastUpdated = Date()
                    self.hasData = true
                    self.isFetching = false
                    print("[WeatherManager] fetchWeather() completed successfully. UI updated on main thread.")
                }
            } catch {
                print("[WeatherManager] Primary fetch error: \(error.localizedDescription)")
                let primaryErrStr = error.localizedDescription
                
                // If it fails, fallback to a sensible default (e.g. London / Greenwich coordinates)
                do {
                    print("[WeatherManager] Initiating fallback fetch (London: 51.5074, -0.1278)...")
                    let weather = try await fetchWeatherData(lat: 51.5074, lon: -0.1278)
                    
                    runOnMainThread { [weak self] in
                        guard let self = self else { return }
                        self.cityName = "London (Fallback)"
                        self.currentTemp = weather.current.temperature_2m
                        self.weatherCode = weather.current.weather_code
                        self.hourlyTemps = Array(weather.hourly.temperature_2m.prefix(12))
                        self.hourlyCodes = Array(weather.hourly.weather_code.prefix(12))
                        self.lastUpdated = Date()
                        self.hasData = true
                        self.errorMessage = nil
                        self.isFetching = false
                        print("[WeatherManager] Fallback completed and updated on main thread.")
                    }
                } catch {
                    print("[WeatherManager] Fallback weather fetch also failed: \(error.localizedDescription)")
                    let fallbackErrStr = error.localizedDescription
                    runOnMainThread { [weak self] in
                        guard let self = self else { return }
                        self.errorMessage = "Fetch Failed: \(primaryErrStr) (Fallback failed: \(fallbackErrStr))"
                        self.isFetching = false
                    }
                }
            }
        }
    }
    
    private func runOnMainThread(_ block: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            RunLoop.main.perform(block)
        }
    }
    
    private func fetchLocation() async throws -> GeoResponse {
        do {
            // Try FreeIPAPI first (generous rate limits, HTTPS)
            guard let url = URL(string: "https://freeipapi.com/api/json") else {
                throw URLError(.badURL)
            }
            let (data, _) = try await session.data(from: url)
            let freeGeo = try JSONDecoder().decode(FreeGeoResponse.self, from: data)
            return GeoResponse(latitude: freeGeo.latitude, longitude: freeGeo.longitude, city: freeGeo.cityName)
        } catch {
            print("Primary geolocator failed: \(error.localizedDescription). Trying secondary...")
            
            // Fallback to ipapi.co
            guard let url = URL(string: "https://ipapi.co/json/") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("WeatherOverlayApp/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, _) = try await session.data(for: request)
            return try JSONDecoder().decode(GeoResponse.self, from: data)
        }
    }
    
    private func fetchWeatherData(lat: Double, lon: Double) async throws -> WeatherResponse {
        let posixLocale = Locale(identifier: "en_US_POSIX")
        let latStr = String(format: "%.6f", locale: posixLocale, lat)
        let lonStr = String(format: "%.6f", locale: posixLocale, lon)
        
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latStr)&longitude=\(lonStr)&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code&forecast_days=1"
        
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

// JSON Structures for Decoding
struct GeoResponse: Codable {
    let latitude: Double
    let longitude: Double
    let city: String?
}

struct FreeGeoResponse: Codable {
    let latitude: Double
    let longitude: Double
    let cityName: String?
}

struct WeatherResponse: Codable {
    let current: CurrentWeather
    let hourly: HourlyWeather
    
    struct CurrentWeather: Codable {
        let temperature_2m: Double
        let weather_code: Int
    }
    
    struct HourlyWeather: Codable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
    }
}
