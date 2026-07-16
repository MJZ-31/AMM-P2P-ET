const { WorkloadModuleBase } = require("@hyperledger/caliper-core")

class BuyWorkload extends WorkloadModuleBase {
    constructor() {
        super()
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext)

        // Generate a random amount of ETokens to sell and approve it.
        this.EAmount = `${BigInt(Math.trunc(Math.random() * 1e19))}`
        await this.sutAdapter.sendRequests([
            {
                contract: "EToken",
                verb: "approve",
                args: ["0xa15bb66138824a1c7167f5e85b957d04dd34e468", this.EAmount]
            }
        ])
    }

    async submitTransaction() {
        await this.sutAdapter.sendRequests([
            {
                contract: "EnergyAMM",
                verb: "sell",
                args: [this.EAmount]
            }
        ])
    }

    async cleanupWorkloadModule() {
        // Reset the market by buying the same amount of ETokens.
        await this.sutAdapter.sendRequests([
            {
                contract: "MToken",
                verb: "approve",
                args: ["0xa15bb66138824a1c7167f5e85b957d04dd34e468", `${BigInt(1e50)}`]
            },
            {
                contract: "EnergyAMM",
                verb: "buy",
                args: [this.EAmount]
            }
        ])
    }
}

function createWorkloadModule() {
    return new BuyWorkload()
}

module.exports.createWorkloadModule = createWorkloadModule
