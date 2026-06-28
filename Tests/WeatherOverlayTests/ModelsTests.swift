import XCTest
@testable import WeatherOverlayCore

final class ModelsTests: XCTestCase {

    func testWeatherResponse_decoding() throws {
        let json = """
        {
          "current": {
            "temperature_2m": 22.5,
            "weather_code": 0,
            "is_day": 1
          },
          "hourly": {
            "time": ["2026-06-28T00:00"],
            "temperature_2m": [18.0],
            "weather_code": [0]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)

        XCTAssertEqual(response.current.temperature_2m, 22.5)
        XCTAssertEqual(response.current.weather_code, 0)
        XCTAssertEqual(response.current.is_day, 1)
        XCTAssertEqual(response.hourly.time.count, 1)
        XCTAssertEqual(response.hourly.temperature_2m.first, 18.0)
        XCTAssertEqual(response.hourly.weather_code.first, 0)
    }

    func testWeatherResponse_decodingNight() throws {
        let json = """
        {
          "current": {
            "temperature_2m": 10.0,
            "weather_code": 61,
            "is_day": 0
          },
          "hourly": {
            "time": ["2026-06-28T00:00", "2026-06-28T01:00"],
            "temperature_2m": [10.0, 9.5],
            "weather_code": [61, 61]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)

        XCTAssertEqual(response.current.is_day, 0)
        XCTAssertEqual(response.current.weather_code, 61)
        XCTAssertEqual(response.hourly.temperature_2m.count, 2)
    }

    func testGeoResponse_decoding() throws {
        let json = """
        {
          "latitude": 51.5074,
          "longitude": -0.1278,
          "city": "London"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GeoResponse.self, from: json)

        XCTAssertEqual(response.latitude, 51.5074)
        XCTAssertEqual(response.longitude, -0.1278)
        XCTAssertEqual(response.city, "London")
    }

    func testGeoResponse_decodingMissingCity() throws {
        let json = """
        {
          "latitude": 40.7128,
          "longitude": -74.0060
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GeoResponse.self, from: json)

        XCTAssertEqual(response.latitude, 40.7128)
        XCTAssertNil(response.city)
    }

    func testFreeGeoResponse_decoding() throws {
        let json = """
        {
          "latitude": 48.8566,
          "longitude": 2.3522,
          "cityName": "Paris"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FreeGeoResponse.self, from: json)

        XCTAssertEqual(response.latitude, 48.8566)
        XCTAssertEqual(response.longitude, 2.3522)
        XCTAssertEqual(response.cityName, "Paris")
    }

    func testGeocodingResponse_decoding() throws {
        let json = """
        {
          "results": [
            {
              "name": "Mumbai",
              "latitude": 19.0760,
              "longitude": 72.8777,
              "country": "India",
              "admin1": "Maharashtra"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GeocodingResponse.self, from: json)

        XCTAssertEqual(response.results?.count, 1)
        let result = try XCTUnwrap(response.results?.first)
        XCTAssertEqual(result.name, "Mumbai")
        XCTAssertEqual(result.latitude, 19.0760)
        XCTAssertEqual(result.longitude, 72.8777)
        XCTAssertEqual(result.country, "India")
        XCTAssertEqual(result.admin1, "Maharashtra")
    }

    func testGeocodingResponse_decodingEmptyResults() throws {
        let json = """
        {
          "results": []
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GeocodingResponse.self, from: json)

        XCTAssertEqual(response.results?.count, 0)
    }

    func testManualLocation_codableRoundTrip() throws {
        let location = ManualLocation(name: "Tokyo", latitude: 35.6762, longitude: 139.6503)

        let data = try JSONEncoder().encode(location)
        let decoded = try JSONDecoder().decode(ManualLocation.self, from: data)

        XCTAssertEqual(decoded.name, "Tokyo")
        XCTAssertEqual(decoded.latitude, 35.6762)
        XCTAssertEqual(decoded.longitude, 139.6503)
    }

    func testManualLocation_equality() {
        let a = ManualLocation(name: "Paris", latitude: 48.8566, longitude: 2.3522)
        let b = ManualLocation(name: "Paris", latitude: 48.8566, longitude: 2.3522)
        let c = ManualLocation(name: "London", latitude: 51.5074, longitude: -0.1278)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testManualLocation_persistence() throws {
        let key = "WeatherOverlay.manualLocation"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: key)

        let loadedBefore = ManualLocation.load()
        XCTAssertNil(loadedBefore)

        let location = ManualLocation(name: "Berlin", latitude: 52.5200, longitude: 13.4050)
        ManualLocation.save(location)

        let loadedAfter = ManualLocation.load()
        XCTAssertEqual(loadedAfter, location)

        ManualLocation.save(nil)
        let loadedAfterClear = ManualLocation.load()
        XCTAssertNil(loadedAfterClear)

        defaults.removeObject(forKey: key)
    }
}
