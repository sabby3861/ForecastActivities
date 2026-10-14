.PHONY: project test test-xcode clean

# First available iPhone simulator. Override with: make test-xcode SIMULATOR_ID=<udid>
SIMULATOR_ID ?= $(shell xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next(x['udid'] for k,v in d.items() if 'iOS' in k for x in v if x['name'].startswith('iPhone')))")

## Generate ForecastActivities.xcodeproj from project.yml (requires: brew install xcodegen)
project:
	xcodegen generate

## Run the package tests on macOS (no simulator needed)
test:
	cd Packages/ActivityKit && swift test

## Run the same tests through the app scheme on an iPhone simulator
test-xcode:
	xcodebuild test -project ForecastActivities.xcodeproj -scheme ForecastActivities -destination 'id=$(SIMULATOR_ID)'

clean:
	rm -rf Packages/ActivityKit/.build DerivedData
