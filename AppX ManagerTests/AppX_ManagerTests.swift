//
//  AppX_ManagerTests.swift
//  AppX ManagerTests
//
//  Created by Hrithik Kumar V on 15/08/26.
//

import Testing
import Foundation
@testable import AppX_Manager

struct AppX_ManagerTests {

    @Test func gemListParsingSkipsDefaultGems() async throws {
        let output = """
        bigdecimal (default: 1.4.1)
        bundler (2.5.6)
        json (default: 2.1.0)
        """
        let parsed = GemScanner.parseList(output)
        #expect(parsed.count == 1)
        #expect(parsed.first?.0 == "bundler")
        #expect(parsed.first?.1 == "2.5.6")
    }

    @Test func gemListParsingTakesFirstOfMultipleVersions() async throws {
        let parsed = GemScanner.parseList("rake (13.4.2, 12.3.3)")
        #expect(parsed.first?.1 == "13.4.2")
    }

    @Test func gemOutdatedParsing() async throws {
        let output = """
        CFPropertyList (2.3.6 < 4.0.0)
        bundler (1.17.2 < 4.0.18)
        """
        let parsed = GemScanner.parseOutdated(output)
        #expect(parsed["CFPropertyList"] == "4.0.0")
        #expect(parsed["bundler"] == "4.0.18")
    }

    @Test func homebrewOutdatedDecoding() async throws {
        let json = """
        {
          "formulae": [
            { "name": "node", "installed_versions": ["20.11.0"], "current_version": "22.6.0", "pinned": false, "pinned_version": null }
          ],
          "casks": [
            { "name": "docker", "installed_versions": ["4.29.0"], "current_version": "4.33.0", "pinned": false, "pinned_version": null }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(HomebrewScanner.OutdatedResponse.self, from: data)
        #expect(decoded.formulae.first?.name == "node")
        #expect(decoded.formulae.first?.currentVersion == "22.6.0")
        #expect(decoded.casks.first?.currentVersion == "4.33.0")
    }

}
