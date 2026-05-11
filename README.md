## Script to download and tar known packages in a Tails

```
./build_offline_packages.sh -f packages.txt
```

To create `packages.txt` you can first `apt install` the required packages in a tails machine, and then do the following:

```
cd /var/cache/apt
sha256sum *.deb
```

And then copy/paste that output to packages.txt
