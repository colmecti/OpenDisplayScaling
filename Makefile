.PHONY: build test package clean
build:
	./scripts/build.sh
test:
	./scripts/test.sh
package: build test
	./scripts/package.sh
clean:
	rm -rf build dist
