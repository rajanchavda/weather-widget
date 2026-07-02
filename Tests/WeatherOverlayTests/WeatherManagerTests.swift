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
        XCTAssertEqual(manager.hourlyTemps.first, 18.0)
        XCTAssertEqual(manager.cityName, "Paris")
        XCTAssertFalse(manager.isNight)
        XCTAssertTrue(manager.hasData)
        XCTAssertNil(manager.errorMessage)
        XCTAssertFalse(manager.isFetching)
        XCTAssertNotNil(manager.lastUpdated)
    }

    // MARK: - Geo Failure Falls Back to London

    func testFetchWeather_geoFailure_fallsBackToLondon() async throws {
        let weatherData = weatherJSON()
        let fetchExpectation = expectation(description: "fallback fetch completes")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                throw URLError(.cannotFindHost)
            }
            if urlString.contains("open-meteo.com") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherData)
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)
        manager.$cityName
            .dropFirst()
            .sink { city in
                if city == "London (Fallback)" {
                    fetchExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()

        await fulfillment(of: [fetchExpectation], timeout: 3.0)

        XCTAssertEqual(manager.cityName, "London (Fallback)")
        XCTAssertEqual(manager.currentTemp, 22.5)
        XCTAssertTrue(manager.hasData)
        XCTAssertNil(manager.errorMessage)
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
        XCTAssertEqual(manager.hourlyPrecipitation.first, 0.0)
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

        var requestCount = 0

        URLProtocolMock.responseDelay = 0.3
        URLProtocolMock.delayedURLs = ["open-meteo.com"]
        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("freeipapi.com") || urlString.contains("ipapi.co") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, geoData)
            }
            if urlString.contains("open-meteo.com") {
                requestCount += 1
                if requestCount == 1 {
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherJSON1)
                } else {
                    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, weatherJSON2)
                }
            }
            fatalError("Unexpected request: \(urlString)")
        }

        manager = WeatherManager(session: .mock)

        let secondFetchDone = expectation(description: "second fetch weather call made")

        manager.$currentTemp
            .dropFirst()
            .sink { temp in
                if temp == 30.0 {
                    secondFetchDone.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.fetchWeather()
        manager.fetchWeather()

        await fulfillment(of: [secondFetchDone], timeout: 5.0)

        XCTAssertEqual(manager.currentTemp, 30.0)
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

    // MARK: - JSON Fixtures

    private func freeGeoJSON() -> Data {
        """
        {"latitude": 48.8566, "longitude": 2.3522, "cityName": "Paris"}
        """.data(using: .utf8)!
    }

    private func weatherJSON() -> Data {
        """
        {
          "current": { "temperature_2m": 22.5, "weather_code": 0, "is_day": 1 },
          "hourly": {
            "time": ["2026-06-28T00:00","2026-06-28T01:00","2026-06-28T02:00","2026-06-28T03:00","2026-06-28T04:00","2026-06-28T05:00","2026-06-28T06:00","2026-06-28T07:00","2026-06-28T08:00","2026-06-28T09:00","2026-06-28T10:00","2026-06-28T11:00","2026-06-28T12:00","2026-06-28T13:00","2026-06-28T14:00"],
            "temperature_2m": [18.0,17.5,16.8,16.2,15.9,16.5,18.1,20.0,22.1,24.3,25.8,26.9,27.5,27.8,27.2],
            "weather_code": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            "precipitation": [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
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
