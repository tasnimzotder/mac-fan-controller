.PHONY: test build dev demo dmg probe

test:
	swift test -Xswiftc -warnings-as-errors
build:
	./tools/build-app.sh
dev: build
	open "dist/Mac Fan Controller.app" --args --show
demo: build
	open "dist/Mac Fan Controller.app" --args --demo --show
dmg:
	./tools/build-dmg.sh
probe: build
	"dist/Mac Fan Controller.app/Contents/MacOS/mac-fan-controller" --probe
