import { handler } from '../lib/http.js';

/** Contract addresses and chain, so redeploys don't need an app update. */
export default handler('GET', async () => ({
  chainId: 10143,
  rpc: process.env.RPC_URL ?? 'https://testnet-rpc.monad.xyz',
  explorer: 'https://testnet.monadexplorer.com',
  game: process.env.GAME_ADDRESS ?? null,
  characters: process.env.CHARACTERS_ADDRESS ?? null,
  territory: process.env.TERRITORY_ADDRESS ?? null,
  lab: process.env.LAB_ADDRESS ?? null,
  crews: process.env.CREWS_ADDRESS ?? null,
  season: process.env.SEASON_ADDRESS ?? null,
  market: process.env.MARKET_ADDRESS ?? null,
  bounties: process.env.BOUNTIES_ADDRESS ?? null,
  raids: process.env.RAIDS_ADDRESS ?? null,
}));
