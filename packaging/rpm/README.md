# Building RPMs

The `Makefile` contains steps that will build RPMs using the locally-configured `rpmbuild` environment.

However, a better approach is to use [mock](https://github.com/rpm-software-management/mock/wiki) which ensures all packages are built in a standard, reproducible environment, and also allows building for targets other than that of the local machine.

The steps to build RPMs with mock are:

* Create tarball + generate spec file from template

    ```bash
    cd packaging/rpm
    make clean && make buildtargz
    ```

* Create SRPM from tarball and spec file

    ```bash
    mock -r epel-7-x86_64 --buildsrpm --spec qpsmtpd.spec --sources build
    mv /var/lib/mock/epel-7-x86_64/result/*.src.rpm build
    ```

3. Build RPMs from SRPM

    ```bash
    mock -r epel-7-x86_64 build/*.src.rpm
    mv /var/lib/mock/epel-7-x86_64/result/*.rpm build
    ```

This builds packages named using the content of the `PACKAGE`, `VERSION`, and `RELEASE` files in the `packaging/rpm` directory.

These can be overridden on the command-line when building the tarball.

For example, to append the local git commit hash to the `RELEASE`:

```bash
make clean && make buildtargz RELEASE="$(<"RELEASE").$(git rev-parse --short HEAD)"
```

This will produce a tarball named something like `qpsmtpd-0.96-1.83b6aaf.tar.gz`
