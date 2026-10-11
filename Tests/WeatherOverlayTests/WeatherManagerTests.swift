import XCTest
import Combine
@testable import WeatherOverlayCore

@MainActor
final class WeatherManagerTests: XCTestCase {
    var manager: WeatherManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        cancellables = []
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.responseDelay = 0
        URLProtocolMock.delayedURLs = []
        UserDefaults.standard.removeObject(forKey: "WeatherOverlay.savedLocations")
        UserDefaults.standard.removeObject(forKey: "WeatherOverlay.manualLocation")
        UserDefaults.standard.removeObject(forKey: "WeatherOverlay.activeLocationId")
    }

    override func tearDown() async throws {
        manager = nil
        cancellables = nil
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.responseDelay = 0
        URLProtocolMock.delayedURLs = []
        try await super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        let m = WeatherManager(session: .mock)
        XCTAssertEqual(m.currentTemp, 0.0)
        XCTAssertEqual(m.weatherCode, 0)
        XCTAssertTrue(m.hourlyTemps.isEmpty)
        XCTAssertEqual(m.cityName, "Detecting...")
        XCTAssertFalse(m.isNight)
        XCTAssertFalse(m.isFetching)
        XCTAssertFalse(m.hasData)
        XCTAssertNil(m.errorMessage)
        XCTAssertNil(m.lastUpdated)
        XCTAssertEqual(m.currentHourIndex, -1)
    }

    // MARK: - Successful Fetch

    func testFetchWeather_success() async throws {
        let geoData = freeGeoJSON()
        let weatherData = weatherJSON()

        let fetchExpectation = expectation(description: "fetchWeather completes")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.$currentTemp
            .dropFirst()
            .sink { temp in
                if temp != 0 {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertEqual(manager.currentTemp, 22.5)
        XCTAssertEqual(manager.weatherCode, 0)
        XCTAssertEqual(manager.hourlyTemps.count, 12)
        XCTAssertEqual(manager.currentHourIndex, 0, "Hourly window should start at the current hour")
        XCTAssertFalse(manager.hourlyTimes.isEmpty)
        XCTAssertFalse(manager.isStale)
        XCTAssertEqual(manager.hourlyTemps.first, 22.5, "Current-hour slice should start with the marked current-hour temp")
        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertFalse(manager.isNight)
        XCTAssertTrue(manager.hasData)
        XCTAssertNil(manager.errorMessage)
        XCTAssertFalse(manager.isFetching)
        XCTAssertNotNil(manager.lastUpdated)
        XCTAssertNotNil(manager.forecastUtcOffsetSeconds)
    }

    // MARK: - Fetch Failure Keeps Last Good Data

    /// Serves geo + weather normally, or fails every request while `failing` is set.
    private final class FailureSwitch: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var failing: Bool {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private func installSwitchableHandler() -> FailureSwitch {
        let failure = FailureSwitch()
        let weatherData = weatherJSON()
        let geoData = freeGeoJSON()
        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if failure.failing { throw URLError(.notConnectedToInternet) }
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("/v1/forecast") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            throw URLError(.badServerResponse)
        }
        return failure
    }

    private func fetchAndWait() async {
        let finished = expectation(description: "fetch finished")
        let subscription = manager.$isFetching
            .dropFirst()
            .filter { !$0 }
            .first()
            .sink { _ in finished.fulfill() }
        manager.fetchWeather()
        await fulfillment(of: [finished], timeout: 3.0)
        subscription.cancel()
    }

    func testFetchFailure_withoutPriorData_reportsErrorAndNeverSubstitutesAnotherCity() async throws {
        let forecastRequested = expectation(description: "no forecast may be requested for a substitute city")
        forecastRequested.isInverted = true

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("open-meteo.com") { forecastRequested.fulfill() }
            throw URLError(.cannotFindHost)
        }

        manager = WeatherManager(session: .mock)
        await fetchAndWait()
        await fulfillment(of: [forecastRequested], timeout: 0.3)

        XCTAssertFalse(manager.hasData)
        XCTAssertFalse(manager.isStale)
        XCTAssertTrue(manager.errorMessage?.contains("Fetch Failed") ?? false)
        XCTAssertNotEqual(manager.cityName, "London (Fallback)")
    }

    func testFetchFailure_afterSuccess_keepsLastGoodDataAsStale() async throws {
        let failure = installSwitchableHandler()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()
        XCTAssertTrue(manager.hasData)
        XCTAssertFalse(manager.isStale)
        let goodCity = manager.cityName
        let goodUpdate = manager.lastUpdated

        failure.failing = true
        await fetchAndWait()

        XCTAssertTrue(manager.hasData, "Last good data must stay on screen")
        XCTAssertTrue(manager.isStale)
        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(manager.currentTemp, 22.5)
        XCTAssertEqual(manager.cityName, goodCity)
        XCTAssertEqual(manager.lastUpdated, goodUpdate, "A failed refresh must not move the last-updated time")
        XCTAssertFalse(manager.isFetching)
    }

    func testFetchFailure_recoveryClearsStale() async throws {
        let failure = installSwitchableHandler()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()
        failure.failing = true
        await fetchAndWait()
        XCTAssertTrue(manager.isStale)

        failure.failing = false
        await fetchAndWait()
        XCTAssertFalse(manager.isStale)
        XCTAssertTrue(manager.hasData)
        XCTAssertNil(manager.errorMessage)
    }

    func testFetchFailure_dataOlderThanLimitIsDropped() async throws {
        let failure = installSwitchableHandler()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()
        manager.lastUpdated = Date().addingTimeInterval(-WeatherManager.maxStaleAge - 60)

        failure.failing = true
        await fetchAndWait()

        XCTAssertFalse(manager.hasData)
        XCTAssertFalse(manager.isStale)
        XCTAssertTrue(manager.hourlyTemps.isEmpty)
        XCTAssertNotNil(manager.errorMessage)
    }

    func testFetchFailure_afterSwitchingLocation_doesNotShowPreviousCity() async throws {
        let failure = installSwitchableHandler()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()
        XCTAssertTrue(manager.hasData)

        failure.failing = true
        let finished = expectation(description: "fetch for new location finished")
        let subscription = manager.$isFetching.dropFirst().filter { !$0 }.first().sink { _ in finished.fulfill() }
        manager.addSavedLocation(SavedLocation(id: UUID(), name: "Mumbai", latitude: 19.07, longitude: 72.87))
        await fulfillment(of: [finished], timeout: 3.0)
        subscription.cancel()

        XCTAssertFalse(manager.hasData, "Another location's data must not stand in for the selected one")
        XCTAssertFalse(manager.isStale)
        XCTAssertNotNil(manager.errorMessage)
    }

    // MARK: - Full Network Error

    func testFetchWeather_networkError_setsError() async throws {
        let fetchExpectation = expectation(description: "error fetch completes")

        URLProtocolMock.requestHandler = { request in
            throw URLError(.notConnectedToInternet)
        }

        manager = WeatherManager(session: .mock)
        manager.$errorMessage
            .dropFirst()
            .sink { error in
                if error != nil {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertFalse(manager.isFetching)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(manager.errorMessage?.contains("Fetch Failed") ?? false)
    }

    // MARK: - Manual Location Override

    func testFetchWeather_manualLocationOverridesGeo() async throws {
        let weatherData = weatherJSON()

        let fetchExpectation = expectation(description: "manual location fetch completes")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                XCTFail("Should not call geo API when manual location is set")
                throw URLError(.badURL)
            }
            if urlString.contains("open-meteo.com") {
                XCTAssertTrue(urlString.contains("forecast_days=2"), "Should request 2 forecast days for a full forward window")
                XCTAssertTrue(urlString.contains("48.8566"), "Should use Paris coordinates")
                XCTAssertTrue(urlString.contains("2.3522"), "Should use Paris coordinates")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.manualLocation = ManualLocation(name: "Paris", latitude: 48.8566, longitude: 2.3522)

        manager.$cityName
            .dropFirst()
            .sink { city in
                if city == "Paris" {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertTrue(manager.hasData)
    }

    // MARK: - Search City

    func testSearchCity_success() async throws {
        let geocodingData = geocodingJSON()

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("geocoding-api.open-meteo.com"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geocodingData)
        }

        let manager = WeatherManager(session: .mock)
        let result = try await manager.searchCity("Mumbai")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Mumbai, Maharashtra")
        XCTAssertEqual(result?.latitude, 19.0760)
        XCTAssertEqual(result?.longitude, 72.8777)
    }

    func testSearchCity_noResults() async throws {
        let json = """
        { "results": [] }
        """.data(using: .utf8)!

        URLProtocolMock.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let manager = WeatherManager(session: .mock)
        let result = try await manager.searchCity("Atlantis")

        XCTAssertNil(result)
    }

    func testSearchCity_emptyQuery() async throws {
        let manager = WeatherManager(session: .mock)
        do {
            _ = try await manager.searchCity("")
            XCTFail("Expected error for empty query")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testSearchCity_networkError() async throws {
        URLProtocolMock.requestHandler = { request in
            throw URLError(.timedOut)
        }

        let manager = WeatherManager(session: .mock)
        do {
            _ = try await manager.searchCity("Paris")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    // MARK: - start() with Timer

    func testStart_setsFetching() {
        URLProtocolMock.requestHandler = { request in
            throw URLError(.notConnectedToInternet)
        }

        manager = WeatherManager(session: .mock)
        XCTAssertFalse(manager.isFetching)

        manager.start()

        XCTAssertTrue(manager.isFetching)
    }

    // MARK: - currentPrecipitation

    func testCurrentPrecipitation_returnsValue() {
        let manager = WeatherManager(session: .mock)
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:00"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        let currentHourStr = df.string(from: now)

        manager.hourlyTimes = [currentHourStr]
        manager.hourlyPrecipitation = [0.5]
        manager.currentHourIndex = 0

        XCTAssertEqual(manager.currentPrecipitation, 0.5)
    }

    func testCurrentPrecipitation_returnsNilWhenNoPrecipData() {
        let manager = WeatherManager(session: .mock)
        manager.hourlyPrecipitation = []
        manager.currentHourIndex = -1
        XCTAssertNil(manager.currentPrecipitation)
    }

    func testCurrentPrecipitation_returnsNilWhenDefaultSentinel() {
        let manager = WeatherManager(session: .mock)
        manager.hourlyPrecipitation = [0.5]
        XCTAssertEqual(manager.currentHourIndex, -1, "Default should be -1")
        XCTAssertNil(manager.currentPrecipitation, "Should return nil when index is -1")
    }

    func testCurrentPrecipitation_returnsNilWhenIndexOutOfBounds() {
        let manager = WeatherManager(session: .mock)
        manager.hourlyPrecipitation = [0.5]
        manager.currentHourIndex = 5
        XCTAssertNil(manager.currentPrecipitation)
    }

    func testCurrentPrecipitation_returnsNilWhenEmptyArrays() {
        let manager = WeatherManager(session: .mock)
        manager.hourlyTimes = []
        manager.hourlyPrecipitation = []
        manager.currentHourIndex = 0
        XCTAssertNil(manager.currentPrecipitation)
    }

    func testFetchWeather_success_setsHourlyPrecipitation() async throws {
        let geoData = freeGeoJSON()
        let weatherData = weatherJSON()

        let fetchExpectation = expectation(description: "fetchWeather sets hourlyPrecipitation")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.$hourlyPrecipitation
            .dropFirst()
            .sink { precip in
                if precip.count == 12 {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertEqual(manager.hourlyPrecipitation.count, 12)
        XCTAssertEqual(manager.currentHourIndex, 0)
        XCTAssertEqual(manager.currentPrecipitation, 0.0)
    }

    // MARK: - Night Detection

    func testFetchWeather_detectsNight_fromAPI() async throws {
        let weatherJSON = """
        {
          "current": {
            "temperature_2m": 15.0,
            "weather_code": 0,
            "is_day": 0
          },
          "hourly": {
            "time": ["2026-06-28T00:00"],
            "temperature_2m": [15.0],
            "weather_code": [0]
          }
        }
        """.data(using: .utf8)!

        let geoData = freeGeoJSON()

        let fetchExpectation = expectation(description: "night detection completes")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherJSON)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.$isNight
            .dropFirst()
            .sink { night in
                if night {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertTrue(manager.isNight)
    }

    // MARK: - Fetch Generation (Stale Response Discard)

    func testFetchWeather_discardsStaleResponse() async throws {
        let weatherJSON1 = """
        {"current":{"temperature_2m":10.0,"weather_code":1,"is_day":1},"hourly":{"time":["2026-06-28T00:00"],"temperature_2m":[10.0],"weather_code":[1]}}
        """.data(using: .utf8)!
        let weatherJSON2 = """
        {"current":{"temperature_2m":30.0,"weather_code":0,"is_day":1},"hourly":{"time":["2026-06-28T00:00"],"temperature_2m":[30.0],"weather_code":[0]}}
        """.data(using: .utf8)!
        let geoData = freeGeoJSON()

        let countLock = NSLock()
        var forecastRequestCount = 0
        let firstForecastRequested = expectation(description: "first forecast request in flight")

        URLProtocolMock.responseDelay = 0.3
        URLProtocolMock.delayedURLs = ["open-meteo.com"]
        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("/v1/forecast") {
                countLock.lock()
                forecastRequestCount += 1
                let count = forecastRequestCount
                countLock.unlock()
                if count == 1 {
                    firstForecastRequested.fulfill()
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherJSON1)
                } else {
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherJSON2)
                }
            }
            if urlString.contains("open-meteo.com") {
                throw URLError(.badServerResponse)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)

        let secondFetchDone = expectation(description: "second fetch weather call made")

        var appliedTemps: [Double] = []
        manager.$currentTemp
            .dropFirst()
            .sink { temp in
                appliedTemps.append(temp)
                if temp == 30.0 {
                    secondFetchDone.fulfill()
                }
            }
            .store(in: &cancellables)

        // Start the second fetch only once the first forecast request is in flight, so the
        // first (stale) response is deterministically the one that must be discarded.
        manager.fetchWeather()
        await fulfillment(of: [firstForecastRequested], timeout: 5.0)
        manager.fetchWeather()

        await fulfillment(of: [secondFetchDone], timeout: 5.0)

        XCTAssertEqual(manager.currentTemp, 30.0)
        XCTAssertFalse(appliedTemps.contains(10.0), "The stale first response must never be applied")
        XCTAssertTrue(manager.hasData)
    }

    // MARK: - AQI Fetch

    func testFetchWeather_withAQI_success() async throws {
        let geoData = freeGeoJSON()
        let weatherData = weatherJSON()
        let aqiData = aqiJSON()

        let fetchExpectation = expectation(description: "fetchWeather with AQI completes")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("air-quality-api.open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, aqiData)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.$aqiValue
            .dropFirst()
            .sink { value in
                if value != nil {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertEqual(manager.aqiValue, 42)
        XCTAssertEqual(manager.aqiLabel, "Moderate")
        XCTAssertEqual(manager.currentTemp, 22.5)
        XCTAssertTrue(manager.hasData)
    }

    func testFetchWeather_withAQI_failureIsNonFatal() async throws {
        let geoData = freeGeoJSON()
        let weatherData = weatherJSON()

        let fetchExpectation = expectation(description: "fetchWeather with AQI failure completes")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("air-quality-api.open-meteo.com") {
                throw URLError(.badServerResponse)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.$currentTemp
            .dropFirst()
            .sink { temp in
                if temp != 0 {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertNil(manager.aqiValue)
        XCTAssertEqual(manager.aqiLabel, "")
        XCTAssertEqual(manager.currentTemp, 22.5)
        XCTAssertTrue(manager.hasData)
    }

    // MARK: - Saved Locations

    func testSavedLocations_initialState() {
        let m = WeatherManager(session: .mock)
        XCTAssertTrue(m.savedLocations.isEmpty)
        XCTAssertNil(m.activeLocationId)
    }

    func testSavedLocations_addAndSwitch() async throws {
        let weatherData = weatherJSON()
        let fetchExpectation = expectation(description: "saved location fetch completes")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                XCTFail("Should not call geo API when saved location is active")
                throw URLError(.badURL)
            }
            if urlString.contains("open-meteo.com") {
                XCTAssertTrue(urlString.contains("48.8566"), "Should use Paris coordinates")
                XCTAssertTrue(urlString.contains("2.3522"), "Should use Paris coordinates")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        let manager = WeatherManager(session: .mock)
        let saved = SavedLocation(id: UUID(), name: "Paris", latitude: 48.8566, longitude: 2.3522)

        manager.$cityName
            .dropFirst()
            .sink { city in
                if city == "Paris" {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.addSavedLocation(saved)

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertEqual(manager.savedLocations.count, 1)
        XCTAssertEqual(manager.savedLocations.first?.name, "Paris")
        XCTAssertEqual(manager.activeLocationId, saved.id)
        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertTrue(manager.hasData)
    }

    func testSavedLocations_switchToAutoLocation() async throws {
        let weatherData = weatherJSON()
        let geoData = freeGeoJSON()

        var geoCallCount = 0
        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                geoCallCount += 1
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        let manager = WeatherManager(session: .mock)
        let saved = SavedLocation(id: UUID(), name: "London", latitude: 51.5074, longitude: -0.1278)
        manager.addSavedLocation(saved)

        let switchExpectation = expectation(description: "switch to auto completes")
        manager.$hasData
            .dropFirst()
            .sink { hasData in
                if hasData && geoCallCount > 0 {
                    switchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.switchToAutoLocation()

        await fulfillment(of: [switchExpectation], timeout: 3.0)

        XCTAssertNil(manager.activeLocationId)
        XCTAssertNil(manager.manualLocation)
        XCTAssertTrue(manager.savedLocations.isEmpty == false)
    }

    func testSavedLocations_addDuplicateIgnored() {
        let manager = WeatherManager(session: .mock)
        let loc1 = SavedLocation(id: UUID(), name: "Paris", latitude: 48.8566, longitude: 2.3522)

        manager.addSavedLocation(loc1)
        XCTAssertEqual(manager.savedLocations.count, 1)

        let loc2 = SavedLocation(id: UUID(), name: "Paris", latitude: 48.8566, longitude: 2.3522)
        manager.addSavedLocation(loc2)
        XCTAssertEqual(manager.savedLocations.count, 1, "Duplicate coordinates should not be added")
    }

    func testSavedLocations_removeActiveFallsBackToAuto() async throws {
        let weatherData = weatherJSON()
        let geoData = freeGeoJSON()
        let fetchExpectation = expectation(description: "fallback fetch after removal")

        var geoCallCount = 0
        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                geoCallCount += 1
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        let manager = WeatherManager(session: .mock)
        let saved = SavedLocation(id: UUID(), name: "Tokyo", latitude: 35.6762, longitude: 139.6503)
        manager.addSavedLocation(saved)

        manager.removeSavedLocation(id: saved.id)

        XCTAssertTrue(manager.savedLocations.isEmpty)
        XCTAssertNil(manager.activeLocationId)
        XCTAssertNil(manager.manualLocation)

        manager.$hasData
            .dropFirst()
            .sink { hasData in
                if hasData {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)
        XCTAssertTrue(manager.hasData)
    }

    func testSavedLocations_switchToNonexistentIdIsNoop() {
        let manager = WeatherManager(session: .mock)
        manager.switchToLocation(id: UUID())
        XCTAssertNil(manager.activeLocationId)
        XCTAssertNil(manager.manualLocation)
    }

    func testSavedLocations_addPersistsActiveLocationId() {
        let manager = WeatherManager(session: .mock)
        let saved = SavedLocation(id: UUID(), name: "Tokyo", latitude: 35.6762, longitude: 139.6503)

        URLProtocolMock.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        manager.addSavedLocation(saved)

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "WeatherOverlay.activeLocationId"),
            saved.id.uuidString,
            "activeLocationId must be persisted when adding a location"
        )

        let restored = WeatherManager(session: .mock)
        XCTAssertEqual(restored.activeLocationId, saved.id)
    }

    func testSavedLocations_removeClearsPersistedActiveLocationId() {
        let manager = WeatherManager(session: .mock)
        let saved = SavedLocation(id: UUID(), name: "Tokyo", latitude: 35.6762, longitude: 139.6503)

        URLProtocolMock.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        manager.addSavedLocation(saved)
        manager.removeSavedLocation(id: saved.id)

        XCTAssertNil(UserDefaults.standard.string(forKey: "WeatherOverlay.activeLocationId"))
        XCTAssertNil(manager.activeLocationId)

        let restored = WeatherManager(session: .mock)
        XCTAssertNil(restored.activeLocationId)
    }

    func testSavedLocations_saveCurrentAsSavedLocation() {
        let manager = WeatherManager(session: .mock)
        manager.cityName = "Mumbai"
        manager.manualLocation = ManualLocation(name: "Mumbai", latitude: 19.0760, longitude: 72.8777)

        manager.saveCurrentAsSavedLocation()

        XCTAssertEqual(manager.savedLocations.count, 1)
        XCTAssertEqual(manager.savedLocations.first?.name, "Mumbai")
        XCTAssertEqual(manager.savedLocations.first?.latitude, 19.0760)
        XCTAssertEqual(manager.activeLocationId, manager.savedLocations.first?.id)
    }

    func testSavedLocations_saveCurrentWithoutManualLocationDoesNothing() {
        let manager = WeatherManager(session: .mock)
        manager.cityName = "Paris"
        manager.manualLocation = nil

        manager.saveCurrentAsSavedLocation()

        XCTAssertTrue(manager.savedLocations.isEmpty)
    }

    func testFetchWeather_withAQI_failure_clearsStaleValue() async throws {
        let geoData = freeGeoJSON()
        let weatherData = weatherJSON()

        let fetchExpectation = expectation(description: "fetchWeather with AQI stale value clears")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("air-quality-api.open-meteo.com") {
                throw URLError(.badServerResponse)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.aqiValue = 42
        manager.aqiLabel = "Moderate"
        manager.$aqiValue
            .dropFirst()
            .sink { value in
                if value == nil {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertNil(manager.aqiValue)
        XCTAssertEqual(manager.aqiLabel, "")
        XCTAssertEqual(manager.currentTemp, 22.5)
    }

    func testFetchWeather_staleAQIFailureDoesNotClearNewerValue() async throws {
        let geoData = freeGeoJSON()
        let weatherData = weatherJSON()
        let aqiData = aqiJSON()

        var aqiRequestCount = 0
        let newerAQISet = expectation(description: "newer AQI value applied")

        // Only delay the first (stale) AQI failure; the second succeeds immediately.
        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("air-quality-api.open-meteo.com") {
                aqiRequestCount += 1
                if aqiRequestCount == 1 {
                    URLProtocolMock.responseDelay = 0.35
                    URLProtocolMock.delayedURLs = ["air-quality-api.open-meteo.com"]
                    throw URLError(.badServerResponse)
                }
                URLProtocolMock.responseDelay = 0
                URLProtocolMock.delayedURLs = []
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, aqiData)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.$aqiValue
            .dropFirst()
            .sink { value in
                if value == 42 {
                    newerAQISet.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather() // gen 1 — AQI fails slowly
        try await Task.sleep(nanoseconds: 50_000_000)
        manager.fetchWeather() // gen 2 — AQI succeeds immediately

        await fulfillment(of: [newerAQISet], timeout: 5.0)
        // Wait long enough for the delayed stale failure to arrive (and be ignored).
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(manager.aqiValue, 42, "Stale AQI failure must not clear a newer successful AQI value")
        XCTAssertEqual(manager.aqiLabel, "Moderate")
    }

    // MARK: - Geo-IP Cache

    /// Serves geo-IP, forecast and AQI requests, counting the geo-IP ones per provider.
    private final class GeoStub: @unchecked Sendable {
        private let lock = NSLock()
        private var _city = "Paris"
        private var _geoFailing = false
        private var _primaryRequests = 0
        private var _secondaryRequests = 0
        private var _forecastURLs: [String] = []
        private var _onGeoRequest: (() -> Void)?
        private var _onForecastRequest: ((String) -> Void)?

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }

        /// City the geo-IP provider reports; each city has its own coordinates.
        var city: String {
            get { locked { _city } }
            set { locked { _city = newValue } }
        }
        /// Fails both geo-IP providers while set. Forecast requests keep working.
        var geoFailing: Bool {
            get { locked { _geoFailing } }
            set { locked { _geoFailing = newValue } }
        }
        var onGeoRequest: (() -> Void)? {
            get { locked { _onGeoRequest } }
            set { locked { _onGeoRequest = newValue } }
        }
        var onForecastRequest: ((String) -> Void)? {
            get { locked { _onForecastRequest } }
            set { locked { _onForecastRequest = newValue } }
        }
        var primaryRequests: Int { locked { _primaryRequests } }
        var secondaryRequests: Int { locked { _secondaryRequests } }
        var forecastURLs: [String] { locked { _forecastURLs } }

        static func latitude(for city: String) -> Double {
            switch city {
            case "Paris": return 48.8566
            case "Berlin": return 52.52
            default: return 10.0
            }
        }

        func install(weatherData: Data) {
            URLProtocolMock.requestHandler = { [self] request in
                let url = request.url!
                let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                switch url.host {
                case "freeipapi.com", "ipapi.co":
                    let isPrimary = url.host == "freeipapi.com"
                    let (city, failing, callback) = locked { () -> (String, Bool, (() -> Void)?) in
                        if isPrimary { _primaryRequests += 1 } else { _secondaryRequests += 1 }
                        return (_city, _geoFailing, _onGeoRequest)
                    }
                    callback?()
                    if failing { throw URLError(.cannotConnectToHost) }
                    let json = "{\"latitude\": \(Self.latitude(for: city)), \"longitude\": 2.0, \"cityName\": \"\(city)\"}"
                    return (ok, json.data(using: .utf8)!)
                case "api.open-meteo.com":
                    let callback = locked { () -> ((String) -> Void)? in
                        _forecastURLs.append(url.absoluteString)
                        return _onForecastRequest
                    }
                    callback?(url.absoluteString)
                    return (ok, weatherData)
                default:
                    // AQI is non-fatal and irrelevant here.
                    throw URLError(.badServerResponse)
                }
            }
        }
    }

    private func installGeoStub() -> GeoStub {
        let stub = GeoStub()
        stub.install(weatherData: weatherJSON())
        return stub
    }

    /// Runs `action`, which must start a fetch, and waits for that fetch to finish.
    private func waitForFetch(after action: () -> Void) async {
        let finished = expectation(description: "fetch finished")
        let subscription = manager.$isFetching
            .dropFirst()
            .filter { !$0 }
            .first()
            .sink { _ in finished.fulfill() }
        action()
        await fulfillment(of: [finished], timeout: 3.0)
        subscription.cancel()
    }

    func testGeoCache_secondAutoRefreshWithinLifetimeMakesNoGeoRequest() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)
        var clock = Date()
        manager.now = { clock }

        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 1)
        XCTAssertEqual(manager.cityName, "Paris")

        // The provider would now answer differently; a cached refresh must not ask it.
        stub.city = "Berlin"
        clock += WeatherManager.geoLocationCacheLifetime - 1
        await fetchAndWait()

        XCTAssertEqual(stub.primaryRequests, 1, "A refresh within the lifetime must reuse the cached location")
        XCTAssertEqual(stub.secondaryRequests, 0)
        XCTAssertEqual(stub.forecastURLs.count, 2, "The forecast itself is still refreshed")
        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertTrue(manager.hasData)
        XCTAssertFalse(manager.isStale)
    }

    func testGeoCache_defaultLifetimeIsOneHour() {
        XCTAssertEqual(WeatherManager.geoLocationCacheLifetime, 3600)
    }

    func testGeoCache_expiredEntryTriggersNewLookup() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)
        var clock = Date()
        manager.now = { clock }

        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 1)

        stub.city = "Berlin"
        clock += WeatherManager.geoLocationCacheLifetime
        await fetchAndWait()

        XCTAssertEqual(stub.primaryRequests, 2, "An expired entry must be looked up again")
        XCTAssertEqual(manager.cityName, "Berlin")

        // The new result starts a new lifetime.
        clock += WeatherManager.geoLocationCacheLifetime - 1
        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 2)
    }

    func testGeoCache_clockMovedBackwardsTriggersNewLookup() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)
        var clock = Date()
        manager.now = { clock }

        await fetchAndWait()
        clock -= 120
        await fetchAndWait()

        XCTAssertEqual(stub.primaryRequests, 2, "An entry dated in the future cannot be trusted as fresh")
    }

    func testGeoCache_forceRefreshBypassesCache() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 1)

        stub.city = "Berlin"
        await waitForFetch { manager.forceRefresh() }

        XCTAssertEqual(stub.primaryRequests, 2, "A forced refresh must look the location up again")
        XCTAssertEqual(manager.cityName, "Berlin")

        // The forced lookup refills the cache for ordinary refreshes.
        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 2)
    }

    func testGeoCache_failedLookupFallsBackToHeldResult() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)
        var clock = Date()
        manager.now = { clock }

        await fetchAndWait()
        XCTAssertEqual(manager.cityName, "Paris")

        // Expired, and both providers are now down.
        clock += WeatherManager.geoLocationCacheLifetime * 5
        stub.geoFailing = true
        await fetchAndWait()

        XCTAssertEqual(stub.primaryRequests, 2)
        XCTAssertEqual(stub.secondaryRequests, 1, "Both providers are tried before falling back")
        XCTAssertTrue(manager.hasData)
        XCTAssertFalse(manager.isStale, "The refresh itself succeeded with the held location")
        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertTrue(stub.forecastURLs.last?.contains("latitude=48.856600") ?? false)

        // The fallback does not renew the entry: the next refresh tries the lookup again.
        stub.geoFailing = false
        stub.city = "Berlin"
        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 3)
        XCTAssertEqual(manager.cityName, "Berlin")
    }

    func testGeoCache_failedLookupWithNothingHeldFailsRefresh() async throws {
        let stub = installGeoStub()
        stub.geoFailing = true
        manager = WeatherManager(session: .mock)

        await fetchAndWait()

        XCTAssertFalse(manager.hasData)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(stub.forecastURLs.isEmpty)
    }

    func testGeoCache_invalidationKeepsEntryAsFallbackAndStartsNoFetch() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()
        let forecastsBefore = stub.forecastURLs.count

        manager.invalidateGeoLocationCache()
        XCTAssertFalse(manager.isFetching, "Invalidating must not start a fetch")

        // The lookup is retried, fails, and the invalidated entry still stands in.
        stub.geoFailing = true
        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 2)
        XCTAssertEqual(stub.forecastURLs.count, forecastsBefore + 1, "Only the explicit refresh fetched")
        XCTAssertTrue(manager.hasData)
        XCTAssertFalse(manager.isStale)
        XCTAssertEqual(manager.cityName, "Paris")

        // Once the lookup works again the new answer replaces it.
        stub.geoFailing = false
        stub.city = "Berlin"
        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 3)
        XCTAssertEqual(manager.cityName, "Berlin")
    }

    func testGeoCache_networkPathUpdateInvalidatesWithoutFetching() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()

        // The monitor's first report describes the path it started on, not a change.
        manager.networkPathDidUpdate(connectionRestored: false)
        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 1)

        // A later update with the path still satisfied (VPN toggle, Wi-Fi change).
        let forecastsBefore = stub.forecastURLs.count
        stub.city = "Berlin"
        manager.networkPathDidUpdate(connectionRestored: false)
        XCTAssertFalse(manager.isFetching, "A path change alone must not start a fetch")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(stub.primaryRequests, 1)
        XCTAssertEqual(stub.forecastURLs.count, forecastsBefore)

        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 2, "The next refresh after a path change looks up again")
        XCTAssertEqual(manager.cityName, "Berlin")
    }

    func testGeoCache_networkRestoredFetchesWithFreshLookup() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()
        manager.networkPathDidUpdate(connectionRestored: false) // initial report

        stub.city = "Berlin"
        await waitForFetch { manager.networkPathDidUpdate(connectionRestored: true) }

        XCTAssertEqual(stub.primaryRequests, 2)
        XCTAssertEqual(manager.cityName, "Berlin")
    }

    func testGeoCache_resumeInvalidates() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)

        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 1)

        manager.pause()
        stub.city = "Berlin"
        await waitForFetch { manager.resume() }

        XCTAssertEqual(stub.primaryRequests, 2, "The machine may have moved while paused")
        XCTAssertEqual(manager.cityName, "Berlin")
    }

    func testGeoCache_savedLocationNeverTouchesCache() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)
        let mumbai = SavedLocation(id: UUID(), name: "Mumbai", latitude: 19.076, longitude: 72.8777)

        await waitForFetch { manager.addSavedLocation(mumbai) }
        await fetchAndWait()
        await waitForFetch { manager.forceRefresh() }

        XCTAssertEqual(stub.primaryRequests, 0, "A saved location never asks geo-IP")
        XCTAssertEqual(stub.secondaryRequests, 0)
        XCTAssertEqual(manager.cityName, "Mumbai")
        XCTAssertTrue(stub.forecastURLs.allSatisfy { $0.contains("latitude=19.076000") })

        // Nothing was cached on its behalf: Auto has to look itself up.
        await waitForFetch { manager.switchToAutoLocation() }
        XCTAssertEqual(stub.primaryRequests, 1)
        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertTrue(stub.forecastURLs.last?.contains("latitude=48.856600") ?? false)
    }

    func testGeoCache_switchingBetweenSavedAndAutoServesTheRightLocation() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)
        let mumbai = SavedLocation(id: UUID(), name: "Mumbai", latitude: 19.076, longitude: 72.8777)

        await fetchAndWait()
        XCTAssertEqual(manager.cityName, "Paris")

        await waitForFetch { manager.addSavedLocation(mumbai) }
        XCTAssertEqual(manager.cityName, "Mumbai")
        XCTAssertTrue(stub.forecastURLs.last?.contains("latitude=19.076000") ?? false)

        await waitForFetch { manager.switchToAutoLocation() }
        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertTrue(stub.forecastURLs.last?.contains("latitude=48.856600") ?? false)
        XCTAssertEqual(stub.primaryRequests, 1, "Back on Auto within the lifetime, the cached lookup is reused")
    }

    func testGeoCache_supersededFetchDoesNotWriteCache() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)
        let mumbai = SavedLocation(id: UUID(), name: "Mumbai", latitude: 19.076, longitude: 72.8777)

        let lookupInFlight = expectation(description: "first geo lookup in flight")
        let supersededFetchContinued = expectation(description: "superseded fetch got its location")
        stub.onGeoRequest = { lookupInFlight.fulfill() }
        stub.onForecastRequest = { url in
            if url.contains("latitude=48.856600") { supersededFetchContinued.fulfill() }
        }
        URLProtocolMock.responseDelay = 0.3
        URLProtocolMock.delayedURLs = ["freeipapi.com"]

        // Auto fetch starts its lookup, then a saved location supersedes it.
        manager.fetchWeather()
        await fulfillment(of: [lookupInFlight], timeout: 3.0)
        stub.onGeoRequest = nil
        await waitForFetch { manager.addSavedLocation(mumbai) }
        XCTAssertEqual(manager.cityName, "Mumbai")

        // The superseded lookup returns and that fetch moves on to its (discarded) forecast.
        await fulfillment(of: [supersededFetchContinued], timeout: 3.0)
        stub.onForecastRequest = nil
        URLProtocolMock.responseDelay = 0
        URLProtocolMock.delayedURLs = []
        XCTAssertEqual(manager.cityName, "Mumbai")

        await waitForFetch { manager.switchToAutoLocation() }
        XCTAssertEqual(stub.primaryRequests, 2, "A superseded fetch must not have filled the cache")
        XCTAssertEqual(manager.cityName, "Paris")
    }

    func testGeoCache_invalidationDuringLookupIsNotLost() async throws {
        let stub = installGeoStub()
        manager = WeatherManager(session: .mock)

        let lookupInFlight = expectation(description: "geo lookup in flight")
        stub.onGeoRequest = { lookupInFlight.fulfill() }
        URLProtocolMock.responseDelay = 0.2
        URLProtocolMock.delayedURLs = ["freeipapi.com"]

        let finished = expectation(description: "fetch finished")
        let subscription = manager.$isFetching
            .dropFirst()
            .filter { !$0 }
            .first()
            .sink { _ in finished.fulfill() }

        // The network changes while the lookup is in flight: its answer may describe the
        // old network, so it serves this refresh but must not be cached as fresh.
        manager.fetchWeather()
        await fulfillment(of: [lookupInFlight], timeout: 3.0)
        stub.onGeoRequest = nil
        manager.invalidateGeoLocationCache()
        await fulfillment(of: [finished], timeout: 3.0)
        subscription.cancel()
        URLProtocolMock.responseDelay = 0
        URLProtocolMock.delayedURLs = []

        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertEqual(stub.primaryRequests, 1)

        await fetchAndWait()
        XCTAssertEqual(stub.primaryRequests, 2, "The refresh after the invalidation must look up again")
    }

    // MARK: - JSON Fixtures

    private func freeGeoJSON() -> Data {
        """
        {"latitude": 48.8566, "longitude": 2.3522, "cityName": "Paris"}
        """.data(using: .utf8)!
    }

    private func weatherJSON() -> Data {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:00"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let currentHour = calendar.component(.hour, from: now)

        var times: [String] = []
        var temps: [String] = []
        var codes: [String] = []
        var precips: [String] = []

        // 48 hours from local midnight so late-day slices still have 12 forward hours.
        for i in 0..<48 {
            guard let date = calendar.date(byAdding: .hour, value: i, to: startOfDay) else { continue }
            times.append("\"\(df.string(from: date))\"")
            // Mark the current hour with a distinctive temperature for assertions.
            let temp = (i == currentHour) ? 22.5 : (18.0 + Double(i % 12) * 0.5)
            temps.append(String(format: "%.1f", temp))
            codes.append("0")
            precips.append("0.0")
        }

        let offset = TimeZone.current.secondsFromGMT()
        return """
        {
          "utc_offset_seconds": \(offset),
          "timezone": "\(TimeZone.current.identifier)",
          "current": { "temperature_2m": 22.5, "weather_code": 0, "is_day": 1 },
          "hourly": {
            "time": [\(times.joined(separator: ","))],
            "temperature_2m": [\(temps.joined(separator: ","))],
            "weather_code": [\(codes.joined(separator: ","))],
            "precipitation": [\(precips.joined(separator: ","))]
          }
        }
        """.data(using: .utf8)!
    }

    private func geocodingJSON() -> Data {
        """
        {"results": [{"name": "Mumbai", "latitude": 19.0760, "longitude": 72.8777, "country": "India", "admin1": "Maharashtra"}]}
        """.data(using: .utf8)!
    }

    private func aqiJSON() -> Data {
        """
        {"current": {"european_aqi": 42}}
        """.data(using: .utf8)!
    }
}
