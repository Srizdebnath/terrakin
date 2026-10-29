// Lets `node --test` run the sources directly: lib files import each other
// as ./x.js (what Vercel's compiler wants); map those to ./x.ts.
import { registerHooks } from 'node:module';

registerHooks({
  resolve(specifier, context, next) {
    try {
      return next(specifier, context);
    } catch (e) {
      if (specifier.startsWith('.') && specifier.endsWith('.js')) return next(specifier.slice(0, -3) + '.ts', context);
      throw e;
    }
  },
});
