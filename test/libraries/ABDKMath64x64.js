const { BigNumber } = require('@ethersproject/bignumber')
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

describe.only('ABDKMath64x64', function() {
	let instance

	before(async function() {
		const factory = await ethers.getContractFactory('ABDKMath64x64Mock')
		instance = await factory.deploy()
		await instance.deployed()
	})

	describe('#fromInt', function() {
		it('returns 64.64 bit representation of given int', async function() {
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
		it('multiplies a 64x64 with an int', async function() {
			const inputs = [Math.floor(Math.random() * 1e6), -Math.floor(Math.random() * 1e6)].map(ethers.BigNumber.from)

			for (let i; i < inputs.length; i++) {
				const bn = await instance.callStatic.fromInt(inputs[i])
				const answer = bn * BigNumber(7)
				expect(await instance.callStatic.muli(bn, BigNumber(7)).to.equal(answer))
			}
		})

		describe('reverts if', function() {
			it('input is too small', async function() {
				await expect(instance.callStatic.muli(-0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFn - 1n, 1)).to.be.reverted
			})

			it('input is too large', async function() {
				await expect(instance.callStatic.muli(0x1000000000000000000000000000000000000000000000000n + 1n, 1)).to.be.reverted
			})

			it('todo: revert if result would overflow')
		})
	})

	describe('#mulu', function() {
		it('multiplies a 64x64 with an unsigned int', async function() {
			const inputs = [Math.floor(Math.random() * 1e6), -Math.floor(Math.random() * 1e6)].map(ethers.BigNumber.from)

			for (let i; i < inputs.length; i++) {
				const bn = await instance.callStatic.fromInt(inputs[i])
				const answer = bn * BigNumber(7)
				expect(await instance.callStatic.mulu(bn, BigNumber(7)).to.equal(answer))
			}
		})

		describe('reverts if', function() {
			it('overflows', async function() {
				await expect(instance.callStatic.mulu(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFn, 2)).to.be.reverted
			})
		})
	})

	describe('#div', function() {
		it('todo')

		describe('reverts if', function() {
			it('y is 0')
			it('overflows')
		})
	})

	describe('#divi', function() {
		it('todo')

		describe('reverts if', function() {
			it('y is 0')
			it('overflows')
		})
	})

	describe('#divu', function() {
		it('todo')

		describe('reverts if', function() {
			it('y is 0')
			it('overflows')
		})
	})

	describe('#neg', function() {
		it('returns the negative', async function(){
			const randomInt = Math.floor(Math.random() * 1e3)
			const input = await instance.callStatic.fromInt(randomInt)
			const answer = BigInt(-input)
			expect(await instance.callStatic.neg(input)).to.equal(answer)
		})

		describe('reverts if', function() {
			it('overflows', async function() {
				await expect(instance.callStatic.neg(-0x80000000000000000000000000000000)).to.be.reverted
			})
		})
	})

	describe('#abs', function() {
		it('returns the absolute |x|', async function() {
			const randomInt = Math.floor(Math.random() * 1e3)
			const input = await instance.callStatic.fromInt(randomInt)
			expect(await instance.callStatic.abs(input)).to.equal(input)
			const randomIntNeg = Math.floor(-Math.random() * 1e3)
			const inputNeg = await instance.callStatic.fromInt(randomIntNeg)
			expect(await instance.callStatic.abs(inputNeg)).to.equal(BigInt(-inputNeg))
		})

		describe('reverts if', function() {
			it('overflows', async function() {
				await expect(instance.callStatic.abs(-0x80000000000000000000000000000000)).to.be.reverted
			})
		})
	})

	describe('#inv', function() {
		it('returns the inverse', async function(){
			const input = await instance.callStatic.fromInt(20)
			const answer = 922337203685477580n
			expect(await instance.callStatic.inv(input)).to.equal(answer)
		})

		describe('reverts if', function() {
			it('x is zero', async function() {
				await (expect(instance.callStatic.inv(0))).to.be.reverted			
			})
			it('overflows', async function() {
				await (expect(instance.callStatic.inv(-1))).to.be.reverted			
			})
		})
	})

	describe('#avg', function() {
		it('calculates average', async function(){
			const inputs = [await instance.callStatic.fromInt(5),
			await instance.callStatic.fromInt(9)]
			const answer = await instance.callStatic.fromInt(7)
			expect(await instance.callStatic.avg(inputs[0], inputs[1])).to.equal(answer)
		})
	})

	describe('#gavg', function() {
		it('calculates average', async function(){
			const inputs = [await instance.callStatic.fromInt(16),
			await instance.callStatic.fromInt(25)]
			const answer = await instance.callStatic.fromInt(20)
			expect(await instance.callStatic.gavg(inputs[0], inputs[1])).to.equal(answer)
		})

		describe('reverts if', function() {
			it('has negative radicant', async function(){
				const inputs = [await instance.callStatic.fromInt(16),
					await instance.callStatic.fromInt(-25)]
				await (expect(instance.callStatic.gavg(inputs[0], inputs[1]))).to.be.reverted
			})
		})
	})

	describe('#pow', function() {
		it('calculates power', async function(){
			const input = await instance.callStatic.fromInt(5)
			expect (await instance.callStatic.pow(input, 5)).to.equal(57646075230342348800000n)
		})

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
