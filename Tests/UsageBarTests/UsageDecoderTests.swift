import XCTest
@testable import UsageBar

final class UsageDecoderTests: XCTestCase {
    func testOpenAIUsageDecoding() throws {
        let data = Data(
            """
            {
              "data": [{
                "results": [{
                  "input_tokens": 1200,
                  "output_tokens": 345,
                  "num_model_requests": 7
                }]
              }]
            }
            """.utf8
        )

        let page = try JSONDecoder().decode(OpenAIUsagePage.self, from: data)
        XCTAssertEqual(page.data[0].results[0].inputTokens, 1200)
        XCTAssertEqual(page.data[0].results[0].outputTokens, 345)
        XCTAssertEqual(page.data[0].results[0].numModelRequests, 7)
    }

    func testAnthropicUsageDecodingHandlesMissingRequests() throws {
        let data = Data(
            """
            {
              "data": [{
                "results": [{
                  "uncached_input_tokens": 1500,
                  "cache_creation": {
                    "ephemeral_1h_input_tokens": 1000,
                    "ephemeral_5m_input_tokens": 500
                  },
                  "cache_read_input_tokens": 200,
                  "output_tokens": 500
                }]
              }]
            }
            """.utf8
        )

        let page = try JSONDecoder().decode(AnthropicUsagePage.self, from: data)
        let result = page.data[0].results[0]
        XCTAssertEqual(result.uncachedInputTokens + result.cacheCreation.total + result.cacheReadInputTokens, 3200)
        XCTAssertEqual(result.requests, 0)
    }

    func testMonitoringValuesDecodeStringAndDouble() throws {
        let data = Data(
            """
            {
              "timeSeries": [{
                "points": [
                  {"value": {"int64Value": "42"}},
                  {"value": {"doubleValue": 8}}
                ]
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(MonitoringResponse.self, from: data)
        XCTAssertEqual(response.timeSeries[0].points.map(\.value.integer).reduce(0, +), 50)
    }

    func testCompactUsageFormatting() {
        XCTAssertEqual(999.compactUsage, "999")
        XCTAssertEqual(1_500.compactUsage, "1.5K")
        XCTAssertEqual(2_000_000.compactUsage, "2.0M")
    }
}
