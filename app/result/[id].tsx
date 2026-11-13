// app/result/[id].tsx — the share page.
// Reads the share by its id (no list query exists on purpose) and shows
// the run's 3 steps as structured JSON. This is the screen the demo
// opens from the share link — and the screen that must still show the
// answer after the app is killed and reopened, because the data comes
// from Convex, not from phone memory.
import { useQuery } from 'convex/react';
import { useLocalSearchParams } from 'expo-router';
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useColorScheme,
} from 'react-native';

import { api } from '../../convex/_generated/api';
import { colors, layout, radius, space, type } from '../../theme';

export default function ResultScreen() {
  const scheme = useColorScheme() ?? 'light';
  const palette = colors[scheme];
  const { id } = useLocalSearchParams<{ id: string }>();

  const shared = useQuery(
    api.shares.getShare,
    typeof id === 'string' && id.length > 0 ? { shareId: id } : 'skip',
  );

  return (
    <ScrollView
      style={{ backgroundColor: palette.background }}
      contentContainerStyle={styles.container}
    >
      <View style={{ maxWidth: layout.maxWidth, width: '100%' }}>
        <Text style={[type.display, { color: palette.ink }]}>
          Shared result
        </Text>

        {shared === undefined ? (
          <ActivityIndicator
            style={styles.loader}
            color={palette.inkSecondary}
          />
        ) : shared === null ? (
          <Text style={[type.body, { color: palette.inkSecondary }]}>
            This share link does not exist or has expired. Shares are
            reachable only by their exact id.
          </Text>
        ) : (
          <View
            style={[
              styles.card,
              {
                backgroundColor: palette.surface,
                borderColor: palette.line,
              },
            ]}
          >
            <Text
              style={[
                type.captionStrong,
                styles.badge,
                shared.run.stubbed
                  ? {
                      backgroundColor: palette.stubBadgeBg,
                      color: palette.stubBadgeInk,
                    }
                  : {
                      backgroundColor: palette.liveBadgeBg,
                      color: palette.liveBadgeInk,
                    },
              ]}
            >
              {shared.run.stubbed ? 'STUBBED' : 'LIVE'}
            </Text>

            <Text
              style={[
                type.body,
                styles.prompt,
                { color: palette.inkSecondary },
              ]}
            >
              {shared.run.prompt}
            </Text>

            {shared.run.steps.map((step, i) => (
              <View key={i} style={styles.step}>
                <Text style={[type.bodyStrong, { color: palette.ink }]}>
                  {step.title}
                </Text>
                <Text style={[type.body, { color: palette.inkSecondary }]}>
                  {step.detail}
                </Text>
              </View>
            ))}

            <Text
              style={[
                type.mono,
                styles.jsonBlock,
                {
                  backgroundColor: palette.surfaceElevated,
                  color: palette.inkSecondary,
                },
              ]}
            >
              {JSON.stringify({ steps: shared.run.steps }, null, 2)}
            </Text>
          </View>
        )}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  badge: {
    alignSelf: 'flex-start',
    borderRadius: radius.md,
    overflow: 'hidden',
    paddingHorizontal: space.sm,
    paddingVertical: space.xs,
  },
  card: {
    borderRadius: radius.xl,
    borderWidth: 1,
    marginTop: space.lg,
    padding: space.lg,
  },
  container: {
    alignItems: 'center',
    padding: layout.screenPadding,
  },
  jsonBlock: {
    borderRadius: radius.md,
    marginTop: space.md,
    padding: space.md,
  },
  loader: {
    marginTop: space.xxl,
  },
  prompt: {
    marginTop: space.md,
  },
  step: {
    marginTop: space.md,
  },
});
