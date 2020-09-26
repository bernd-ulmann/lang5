#!/bin/bash
if [ -d /tmp/lang5 ]; then
    echo "Directory exists - delete and recreate it."
    rm -rf /tmp/lang5
fi

echo "Creating directory structure."
mkdir -p /tmp/lang5/{doc,examples,lib,perl_modules}

echo "Copying files."
cp lang5 lang5.vim README.md INSTALL.md /tmp/lang5
cp examples/* /tmp/lang5/examples
cp lib/* /tmp/lang5/lib
cp -r perl_modules/ /tmp/lang5/perl_modules
cp doc/*.pdf /tmp/lang5/doc/

echo "Compressing distribution kit."
cd /tmp
zip -r lang5.zip lang5 > /dev/null
cd - > /dev/null
mv /tmp/lang5.zip .
rm -rf /tmp/lang5
