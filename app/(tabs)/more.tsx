// app/(tabs)/more.tsx — the placeholder second tab.
// The fleet replaces this screen with the team's real second tab on
// build day. Until then it documents the skeleton: what is wired, what
// is stubbed, and what a human must do tonight (see README).
import { ScrollView, StyleSheet, Text, View, useColorScheme } from 'react-native';

import { colors, layout, space, type } from '../../theme';

export default function MoreScreen() {
  const scheme = useColorScheme() ?? 'light';
  const palette = colors[scheme];

  return (
    <ScrollView
      style={{ backgroundColor: palette.background }}
      contentContainerStyle={styles.container}
    >
      <View style={{ maxWidth: layout.maxWidth, width: '100%' }}>
        <Text style={[type.display, { color: palette.ink }]}>More</Text>
        <Text
          style={[type.body, styles.body, { color: palette.inkSecondary }]}
        >
          Placeholder tab. Replace this screen with the team&apos;s second
          tab on build day — the Home tab already has the full demo flow
          (input → AI call → 3 steps → counter → share link).
        </Text>
        <Text
          style={[type.body, styles.body, { color: palette.inkSecondary }]}
        >
          Wired already: Expo Router tabs, the theme tokens in theme.ts,
          Convex (users / items / aiRuns / shares), the runAi action with
          stub mode, and the Supabase Edge Function that calls Gemini.
          What is NOT wired yet: any account, project or key — humans
          create those tonight (README § &quot;Tonight&quot;).
        </Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  body: {
    marginTop: space.md,
  },
  container: {
    alignItems: 'center',
    padding: layout.screenPadding,
  },
});
