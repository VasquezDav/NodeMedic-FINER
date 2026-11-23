#!/bin/bash

echo "Setting up dependencies"

echo "Cloning jalangi2"
git clone https://github.com/Samsung/jalangi2.git

echo "Creating jalangi2-babel"
mkdir jalangi2-babel
cp -r jalangi2/src jalangi2-babel/
cp jalangi2/package.json jalangi2-babel/

echo "Applying jalangi2-babel patch"
cd jalangi2-babel
# A CRLF patch (from a Windows checkout with no .gitattributes) makes git apply
# fail silently, leaving jalangi acorn-only so it cannot parse the modern-JS
# driver. Normalize line endings, apply tolerantly, then VERIFY it took.
sed -i 's/\r$//' ../babel-changes.patch
git apply --recount --whitespace=nowarn ../babel-changes.patch \
  || git apply --verbose ../babel-changes.patch
if ! grep -q "babel.transformSync" src/js/instrument/esnstrument.js; then
  echo "ERROR: babel-changes.patch did not apply; esnstrument.js is still acorn-only." >&2
  echo "       (Check that lib/babel-changes.patch still matches upstream jalangi2.)" >&2
  exit 1
fi
echo "Patch applied: esnstrument.js now routes code through Babel before acorn."

echo "Installing npm dependencies"
npm i
# Pin Babel to 7.x (CommonJS). Unpinned, npm now pulls Babel 8 which is ESM-only
# and cannot be require()'d under Node 15 (ERR_REQUIRE_ESM). regenerator-runtime
# is also required by the patch and is not a transitive dep, so install it too.
npm i --save-dev @babel/core@^7.0.0 @babel/preset-env@^7.0.0 regenerator-runtime@^0.14.0
if grep -q '"type"[[:space:]]*:[[:space:]]*"module"' node_modules/@babel/core/package.json; then
  echo "ERROR: @babel/core resolved to an ESM build; Node 15 require() will fail." >&2
  exit 1
fi
echo "Babel 7 (CommonJS) + regenerator-runtime installed."

echo "Installing fuzzer"
cd ../fuzzer
npm i
npm i .
for i in `find -name "*.js"`; do printf "\n// JALANGI DO NOT INSTRUMENT" >> $i; done

echo "Installing NodeExploitSynthesis"
cd ../NodeExploitSynthesis
npm i -D @types/node@latest
cd src/synthesis/operation_types
# operation_types/run.sh uses `set -e`, and a modern tsc exits non-zero on the
# ES5-target type errors (Map/Set/BigInt/Symbol/Array.from/fs) even though it
# still EMITS the JS -- so the script aborts before categories.json is built.
# Compile tolerantly (the emitted JS runs fine), generate the files, and verify.
tsc --target es5 --downlevelIteration build_field_categories.ts || true
node build_field_categories.js
if [ ! -f categories.json ] || [ ! -f lattice.json ]; then
  echo "ERROR: categories.json/lattice.json were not generated." >&2
  exit 1
fi
echo "categories.json + lattice.json generated."

pip3 install z3-solver==4.12.2