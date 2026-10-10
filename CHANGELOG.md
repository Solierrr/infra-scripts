# Changelog

## [0.3.0](https://github.com/Solierrr/infra-scripts/compare/v0.2.0...v0.3.0) (2026-10-10)


### Features

* add service profiles to the local runner ([dbdb55e](https://github.com/Solierrr/infra-scripts/commit/dbdb55e5426210bb52d6d4574bb62997fcd7a939))
* add the local cluster with argo cd ([9a1a307](https://github.com/Solierrr/infra-scripts/commit/9a1a307d27712812fbfab83f28838c6e3e78987c))
* add the local service runner ([#7](https://github.com/Solierrr/infra-scripts/issues/7)) ([7fb5bcd](https://github.com/Solierrr/infra-scripts/commit/7fb5bcd849d98c63d2e39654d89ef56e75066d1e))


### Bug Fixes

* mark the cluster script as executable ([4a70eeb](https://github.com/Solierrr/infra-scripts/commit/4a70eeba1f31cf09201ebe2c252abfa08aad525c))
* read the container port from the dockerfile ([7ae8585](https://github.com/Solierrr/infra-scripts/commit/7ae85859a8be2a980b26fa23d4e6765b267472de))
* stop git bash from rewriting the infisical secret path ([cf92191](https://github.com/Solierrr/infra-scripts/commit/cf92191d81b269934c2c0e675c72b314acf591f3))
* strip carriage returns when reading the exposed port ([771cb74](https://github.com/Solierrr/infra-scripts/commit/771cb74a0359007792676521c4b09221df6b7cbc))

## [0.2.0](https://github.com/Solierrr/infra-scripts/compare/v0.1.0...v0.2.0) (2026-09-30)


### Features

* add mobile environment mapping ([#3](https://github.com/Solierrr/infra-scripts/issues/3)) ([3530f11](https://github.com/Solierrr/infra-scripts/commit/3530f11d0f208f43bed64a121ed59c366bb7c882))
* centralize environment extraction ([#1](https://github.com/Solierrr/infra-scripts/issues/1)) ([eada934](https://github.com/Solierrr/infra-scripts/commit/eada934aa7b86cfd7633f4c8387b13a75aea7763))


### Bug Fixes

* prefer native Infisical CLI and reject cached exports ([c04c6a3](https://github.com/Solierrr/infra-scripts/commit/c04c6a3e0ff5533f07c31e4030f262272669f280))
* prompt for env and reject empty secret exports ([5bff5e2](https://github.com/Solierrr/infra-scripts/commit/5bff5e2c4aed56336c0262845965fc63e15e3ae6))
* trigger releases by command ([d77dea2](https://github.com/Solierrr/infra-scripts/commit/d77dea2f8d77e197690aa26203eaa09d2c6f01e0))
