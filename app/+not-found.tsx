// app/+not-found.tsx — 404 screen, styled from theme.ts tokens.
import { Link, Stack } from 'expo-router';
import { StyleSheet, Text, View, useColorScheme } from 'react-native';

import { colors, space, type } from '../theme';

export default function NotFoundScreen() {
  const scheme = useColorScheme() ?? 'light';
  const palette = colors[scheme];
  return (
    <>
      <Stack.Screen options={{ title: 'Oops!' }} />
      <View
        style={[styles.container, { backgroundColor: palette.background }]}
      >
        <Text style={[type.title, { color: palette.ink }]}>
          This screen doesn&apos;t exist.
        </Text>
        <Link href="/" style={styles.link}>
          <Text style={[type.body, { color: palette.ink }]}>
            Go to home screen!
          </Text>
        </Link>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
    padding: space.xl,
  },
  link: {
    marginTop: space.md,
    paddingVertical: space.md,
  },
});
