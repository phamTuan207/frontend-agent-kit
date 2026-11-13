// app/_layout.tsx — root layout.
// Wires the Convex client. If EXPO_PUBLIC_CONVEX_URL is missing the
// app fails LOUDLY with a full-screen explanation instead of a blank
// screen or a cryptic network error: a missing env var is a setup
// mistake, and the person holding the phone needs to know exactly
// which variable to set. See README § "Tonight".
import { ConvexProvider, ConvexReactClient } from 'convex/react';
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect, useMemo } from 'react';
import { StyleSheet, Text, View, useColorScheme } from 'react-native';
import 'react-native-reanimated';

import { colors, space, type } from '../theme';

export {
  // Catch any errors thrown by the Layout component.
  ErrorBoundary,
} from 'expo-router';

export const unstable_settings = {
  anchor: '(tabs)',
};

// Prevent the splash screen from auto-hiding before asset loading is complete.
SplashScreen.preventAutoHideAsync();

function MissingConvexUrlScreen() {
  const scheme = useColorScheme() ?? 'light';
  const palette = colors[scheme];
  return (
    <View
      style={[styles.missingContainer, { backgroundColor: palette.background }]}
    >
      <Text style={[type.title, { color: palette.ink }]}>
        Setup needed before this app can run
      </Text>
      <Text style={[type.body, styles.missingBody, { color: palette.inkSecondary }]}>
        EXPO_PUBLIC_CONVEX_URL is not set. Create a free Convex project,
        then put its deployment URL in .env as EXPO_PUBLIC_CONVEX_URL and
        restart the app. See README § &quot;Tonight&quot; for the exact
        steps. No key, no account and no project was created by this
        skeleton — a human creates them tonight.
      </Text>
    </View>
  );
}

export default function RootLayout() {
  const [loaded, error] = useFonts({
    SpaceMono: require('../assets/fonts/SpaceMono-Regular.ttf'),
  });

  useEffect(() => {
    if (error) throw error;
  }, [error]);

  useEffect(() => {
    if (loaded) {
      SplashScreen.hideAsync();
    }
  }, [loaded]);

  const convexUrl = process.env.EXPO_PUBLIC_CONVEX_URL;
  const client = useMemo(
    () => (convexUrl ? new ConvexReactClient(convexUrl) : null),
    [convexUrl],
  );

  if (!loaded) {
    return null;
  }

  if (!client) {
    return <MissingConvexUrlScreen />;
  }

  return (
    <ConvexProvider client={client}>
      <Stack>
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen
          name="result/[id]"
          options={{ title: 'Shared result', headerBackTitle: 'Back' }}
        />
      </Stack>
    </ConvexProvider>
  );
}

const styles = StyleSheet.create({
  missingBody: {
    marginTop: space.lg,
  },
  missingContainer: {
    flex: 1,
    justifyContent: 'center',
    padding: space.xl,
  },
});
