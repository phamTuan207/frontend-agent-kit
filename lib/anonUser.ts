// lib/anonUser.ts — anonymous identity for the demo.
// The app has no login. On first launch it mints one UUID, persists it
// in AsyncStorage, and reuses it forever. That stable id is what the
// per-user AI-call counter keys on — without it the counter would reset
// to 0 every time the phone kills and reopens the app.
// The id is an anonymous identifier, not a secret and not a credential.

import AsyncStorage from '@react-native-async-storage/async-storage';
import { randomId } from './randomId';

const ANON_USER_KEY = 'optimus.anonUserId.v1';

export async function getAnonUserId(): Promise<string> {
  const stored = await AsyncStorage.getItem(ANON_USER_KEY);
  if (stored) return stored;
  const fresh = randomId();
  await AsyncStorage.setItem(ANON_USER_KEY, fresh);
  return fresh;
}
