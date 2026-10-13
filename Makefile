.PHONY: project test test-xcode clean

## Generate ForecastActivities.xcodeproj from project.yml (requires: brew install xcodegen)
project:
	xcodegen generate

## Run the package test suite on macOS (no simulator needed)
test:
	cd Packages/ActivityKit && swift test

## Run the same tests through Xcode on an iPhone simulator
test-xcode:
	xcodebuild test -scheme ForecastActivities -destination 'platform=iOS Simulator,name=iPhone 16' | xcpretty || true

clean:
	rm -rf Packages/ActivityKit/.build DerivedData
