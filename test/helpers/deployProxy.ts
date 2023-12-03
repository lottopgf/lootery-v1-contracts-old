import { ERC1967Proxy__factory } from '../../typechain-types'
import { BytesLike, ContractFactory, Signer } from 'ethers'

export async function deployProxy<
    TContractFactory extends ContractFactory,
    TContract = ReturnType<TContractFactory['deploy']>,
>({
    deployer,
    implementation,
    initData,
}: {
    deployer: Signer
    implementation: { new (runner?: Signer): TContractFactory }
    initData: BytesLike
}): Promise<TContract> {
    const impl = await new implementation(deployer).deploy()
    const proxy = await new ERC1967Proxy__factory(deployer).deploy(
        await impl.getAddress(),
        initData,
    )
    return new implementation(deployer).attach(await proxy.getAddress()) as TContract
}
