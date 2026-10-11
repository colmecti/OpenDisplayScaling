.PHONY: build test analyze package clean
build:
	./scripts/build.sh
test:
	./scripts/test.sh
analyze:
	./scripts/analyze.sh
package: build test analyze
	./scripts/package.sh
clean:
	rm -rf build dist
