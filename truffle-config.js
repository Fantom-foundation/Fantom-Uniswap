module.exports = {
	contracts_directory: "./contracts/fantom",
	contracts_build_directory: "./build",
    compilers: {
        solc: {
            version: '^0.5.17',
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 5000000
                }
            }
        }
    },
    networks: {
        development: {
            host: "operavm",
            port: 7545,
            network_id: "4002"
        },
        test: {
            host: "wsapi.testnet.fantom.network",
            port: 80,
            network_id: "4002"
        }
    }
};
