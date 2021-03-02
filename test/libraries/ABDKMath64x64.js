const { expect } = require('chai')

const toFixed = function(bn) {
	return bn.shl(64)
}

const range = function(bits, signed) {
	if (signed) {
		return {
			min: ethers.constants.Zero.sub(ethers.constants.Two.pow(bits / 2 - 1)),
			max: ethers.constants.Two.pow(bits / 2 - 1).sub(ethers.constants.One),
		}
	} else {
		return {
			min: ethers.constants.Zero,
			max: ethers.constants.Two.pow(bits).sub(ethers.constants.One),
		}
	}
}

describe('ABDKMath64x64', function() {
	let instance

	before(async function() {
		const factory = await ethers.getContractFactory('ABDKMath64x64Mock')
		instance = await factory.deploy()
		await instance.deployed()
	})

	describe('#fromInt', function() {
		it('returns 64.64 bit represetation of given int', async function() {
			const inputs = [0, 1, 2, Math.floor(Math.random() * 1e6)].map(
				ethers.BigNumber.from,
			)

			for (let bn of inputs) {
				expect(await instance.callStatic.fromInt(bn)).to.equal(toFixed(bn))
			}
		})

		describe('reverts if', function() {
			it('input is greater than max int128', async function() {
				const { max } = range(128, true)

				await expect(instance.callStatic.fromInt(max)).not.to.be.reverted

				await expect(instance.callStatic.fromInt(max.add(ethers.constants.One)))
					.to.be.reverted
			})

			it('input is less than min int128', async function() {
				const { min } = range(128, true)

				await expect(instance.callStatic.fromInt(min)).not.to.be.reverted

				await expect(instance.callStatic.fromInt(min.sub(ethers.constants.One)))
					.to.be.reverted
			})
		})
	})

	describe('#toInt', function() {
		it('returns 64 bit integer from 64.64 representation of given int', async function() {
			const inputs = [
				-2,
				-1,
				0,
				1,
				2,
				Math.floor(Math.random() * 1e6),
				-Math.floor(Math.random() * 1e6),
			].map(ethers.BigNumber.from)

			for (let bn of inputs) {
				const representation = await instance.callStatic.fromInt(bn)
				expect(await instance.callStatic.toInt(representation)).to.equal(bn)
			}
		})
	})

	describe('#fromUInt', function() {
		it('returns 64.64 bit representation of given uint', async function() {
			const inputs = [0, 1, 2, Math.floor(Math.random() * 1e6)].map(
				ethers.BigNumber.from,
			)

			for (let bn of inputs) {
				expect(await instance.callStatic.fromUInt(bn)).to.equal(toFixed(bn))
			}
		})

		describe('reverts if', function() {
			it('input is greater than max int128', async function() {
				const { max } = range(128, true)

				await expect(instance.callStatic.fromInt(max)).not.to.be.reverted

				await expect(instance.callStatic.fromInt(max.add(ethers.constants.One)))
					.to.be.reverted
			})
		})
	})

	describe('#toUInt', function() {
		it('returns 64 bit integer from 64.64 representation of given uint', async function() {
			const inputs = [1, 2, Math.floor(Math.random() * 1e6)].map(
				ethers.BigNumber.from,
			)

			for (let bn of inputs) {
				const representation = await instance.callStatic.fromUInt(bn)
				expect(await instance.callStatic.toUInt(representation)).to.equal(bn)
			}
		})

		describe('reverts if', function() {
			it('input is negative', async function() {
				const representation = await instance.callStatic.fromInt(
					ethers.BigNumber.from(-1),
				)
				await expect(instance.callStatic.toUInt(representation)).to.be.reverted
			})
		})
	})

	describe('#from128x128', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#to128x128', function() {
		it('todo')
	})

	describe('#add', function() {
		it('adds two 64x64s together', async function() {
			const inputs = [1, 2, Math.floor(Math.random() * 1e6)].map(
				ethers.BigNumber.from,
			)
			const inputs2 = [3, -4, -Math.floor(Math.random() * 1e6)].map(
				ethers.BigNumber.from,
			)

			for (let i; i < inputs.length; i++) {
				const bn = await instance.callStatic.fromInt(inputs[i])
				const bn2 = await instance.callStatic.fromInt(inputs2[i])
				const answer = bn + bn2
				expect(await instance.callStatic.add(bn, bn2)).to.equal(answer)
			}
		})

		describe('reverts if', function() {
			it('result would overflow', async function() {
				const max = await instance.callStatic.fromInt(0x7fffffffffffffffn)
				const one = await instance.callStatic.fromInt(1)

				await expect(instance.callStatic.add(max, one)).to.be.reverted
			})
		})
	})

	describe('#sub', function() {
		it('subtracts two 64x64s', async function() {
			const inputs = [1, 2, Math.floor(Math.random() * 1e6)].map(
				ethers.BigNumber.from,
			)
			const inputs2 = [-3, 4, -Math.floor(Math.random() * 1e6)].map(
				ethers.BigNumber.from,
			)

			for (let i; i < inputs.length; i++) {
				const bn = await instance.callStatic.fromInt(inputs[i])
				const bn2 = await instance.callStatic.fromInt(inputs2[i])
				const answer = bn - bn2
				expect(await instance.callStatic.sub(bn, bn2)).to.equal(answer)
			}
		})

		describe('reverts if', function() {
			it('result would overflow', async function() {
				const max = await instance.callStatic.fromInt(0x7fffffffffffffffn)
				const one = await instance.callStatic.fromInt(-1)

				await expect(instance.callStatic.sub(max, one)).to.be.reverted
			})
		})
	})

	describe('#mul', function() {
		it('multiplies two 64x64s', async function() {
			const inputs = [
				Math.floor(Math.random() * 1e6),
				Math.floor(Math.random() * 1e6),
				-Math.floor(Math.random() * 1e6),
			].map(ethers.BigNumber.from)
			const inputs2 = [
				Math.floor(Math.random() * 1e6),
				-Math.floor(Math.random() * 1e6),
				-Math.floor(Math.random() * 1e6),
			].map(ethers.BigNumber.from)

			for (let i; i < inputs.length; i++) {
				const bn = await instance.callStatic.fromInt(inputs[i])
				const bn2 = await instance.callStatic.fromInt(inputs2[i])
				const answer = bn * bn2
				expect(await instance.callStatic.mul(bn, bn2)).to.equal(answer)
			}
		})

		describe('reverts if', function() {
			it('result would overflow', async function() {
				const halfOfMax = await instance.callStatic.fromInt(
					4611686018427387904n,
				)
				const two = await instance.callStatic.fromInt(2)

				await expect(instance.callStatic.mul(halfOfMax, two)).to.be.reverted
			})
		})
	})

	describe('#muli', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#mulu', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#div', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#divi', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#divu', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#neg', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#abs', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#inv', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#avg', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#gavg', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#pow', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#sqrt', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#log_2', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#ln', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})

	describe('#exp_2', function() {
		it('todo')

		describe('reverts if', function() {
			it('todo')
		})
	})
})
