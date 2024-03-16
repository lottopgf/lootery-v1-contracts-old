import fs from 'node:fs'
import path from 'path'
import { Erc721Metadata } from './Erc721Metadata'

const metadata: Erc721Metadata = {
    name: 'Powerbald v1.5 Ticket',
    image: 'ipfs://bafkreig3n72fjdxof4g5bkctu3k2c5jbneyj4q7ijp6kppu4j6ndbgscvi',
    description: 'POWERBALD LOL',
}

console.log(metadata)
fs.writeFileSync(path.resolve(__dirname, 'metadata.json'), JSON.stringify(metadata), {
    encoding: 'utf-8',
})
