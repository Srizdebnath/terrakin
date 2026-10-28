// Server view of the live weather, to check a client's weather-boosted spawn.
// Mirrors Sky.fromWmo and Conditions.boosted in app/lib/core/conditions.dart,
// with tolerance for small differences between the phone's and our fetch.

const AFF = { grove: 0, tide: 1, forge: 2, rune: 3, prism: 4, volt: 5, stone: 6 } as const;

export function skyFromWmo(code: number): string {
  if (code === 0) return 'clear';
  if (code === 1 || code === 2) return 'partlyCloudy';
  if (code === 3) return 'cloudy';
  if (code === 45 || code === 48) return 'fog';
  if (code >= 51 && code <= 57) return 'drizzle';
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return 'rain';
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return 'snow';
  if (code >= 95) return 'storm';
  return 'cloudy';
}

function skyBoosted(sky: string, night: boolean): number[] {
  switch (sky) {
    case 'clear': return night ? [AFF.rune] : [AFF.forge, AFF.grove];
    case 'partlyCloudy': return [AFF.grove, AFF.prism];
    case 'cloudy': return [AFF.stone];
    case 'fog': return [AFF.stone, AFF.rune];
    case 'drizzle': return [AFF.tide, AFF.grove];
    case 'rain': return [AFF.tide];
    case 'snow': return [AFF.stone, AFF.prism];
    case 'storm': return [AFF.volt, AFF.tide];
    default: return [];
  }
}

export interface ServerWeather { sky: string; plausible: Set<number> }

export async function weatherAt(lat: number, lng: number): Promise<ServerWeather> {
  const url = new URL('https://api.open-meteo.com/v1/forecast');
  url.search = new URLSearchParams({
    latitude: lat.toFixed(3),
    longitude: lng.toFixed(3),
    current: 'temperature_2m,weather_code,wind_speed_10m',
  }).toString();
  const r = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!r.ok) throw new Error(`weather ${r.status}`);
  const j = (await r.json()) as { current: { weather_code: number; temperature_2m: number; wind_speed_10m: number } };
  const sky = skyFromWmo(j.current.weather_code);
  const plausible = new Set<number>([
    ...skyBoosted(sky, false),
    ...skyBoosted(sky, true),
    AFF.rune, // night, give or take the phone's sunset maths
    AFF.prism, // golden hour
  ]);
  if (j.current.wind_speed_10m >= 18) plausible.add(AFF.volt);
  if (j.current.temperature_2m >= 28) plausible.add(AFF.forge);
  return { sky, plausible };
}
