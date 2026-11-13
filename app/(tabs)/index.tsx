// app/(tabs)/index.tsx — Home: the one demo AI flow, end to end.
// One text input, one button, one result area. The flow:
//   input → Convex action runAi → run persisted in aiRuns → this
//   screen re-renders from the useQuery subscription (never from phone
//   memory alone) → counter + share link.
// Kill the app and reopen it: the latest run and the counter are still
// here, because they live in Convex. A STUBBED badge is shown whenever
// the answer came from stub mode; a stubbed answer is never presented
// as a live AI answer.
import { useAction, useMutation, useQuery } from 'convex/react';
import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  useColorScheme,
} from 'react-native';

import { api } from '../../convex/_generated/api';
import type { Id } from '../../convex/_generated/dataModel';
import { getAnonUserId } from '../../lib/anonUser';
import { runAiFlow } from '../../lib/aiClient';
import { randomId } from '../../lib/randomId';
import { colors, layout, radius, space, type } from '../../theme';

function readableError(e: unknown): string {
  if (typeof e === 'object' && e !== null) {
    const data = (e as { data?: { code?: string; message?: string } }).data;
    if (data?.code) return `${data.code}: ${data.message ?? 'Unknown error.'}`;
    if (e instanceof Error) return e.message;
  }
  return 'Unknown error.';
}

export default function HomeScreen() {
  const scheme = useColorScheme() ?? 'light';
  const palette = colors[scheme];

  const [userId, setUserId] = useState<Id<'users'> | null>(null);
  const [prompt, setPrompt] = useState('');
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [setupError, setSetupError] = useState<string | null>(null);

  const ensureUser = useMutation(api.users.ensureUser);
  const runAi = useAction(api.ai.runAi);
  const count = useQuery(
    api.aiRuns.getCount,
    userId ? { userId } : 'skip',
  );
  const latest = useQuery(
    api.aiRuns.getLatest,
    userId ? { userId } : 'skip',
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const anonId = await getAnonUserId();
        if (cancelled) return;
        const uid = await ensureUser({ anonId });
        if (!cancelled) setUserId(uid);
      } catch (e) {
        if (!cancelled) setSetupError(readableError(e));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [ensureUser]);

  async function onSubmit() {
    if (!userId || running || prompt.trim().length === 0) return;
    setRunning(true);
    setError(null);
    try {
      await runAiFlow(runAi, {
        userId,
        prompt: prompt.trim(),
        idempotencyKey: randomId(),
      });
    } catch (e) {
      setError(readableError(e));
    } finally {
      setRunning(false);
    }
  }

  const counterText =
    count === undefined ? 'AI calls used: …' : `AI calls used: ${count}`;

  return (
    <ScrollView
      style={{ backgroundColor: palette.background }}
      contentContainerStyle={styles.container}
    >
      <View style={{ maxWidth: layout.maxWidth, width: '100%' }}>
        <Text style={[type.display, { color: palette.ink }]}>
          Optimus skeleton
        </Text>
        <Text
          style={[
            type.body,
            styles.subtitle,
            { color: palette.inkSecondary },
          ]}
        >
          One input, one AI call, three steps. The answer is saved in
          Convex, so it survives kill-and-reopen.
        </Text>

        {setupError ? (
          <View
            style={[styles.errorBox, { borderColor: palette.danger }]}
          >
            <Text style={[type.body, { color: palette.danger }]}>
              {setupError}
            </Text>
          </View>
        ) : null}

        <TextInput
          style={[
            type.body,
            styles.input,
            {
              backgroundColor: palette.surface,
              borderColor: palette.line,
              color: palette.ink,
            },
          ]}
          placeholder="Ask for a 3-step plan…"
          placeholderTextColor={palette.inkTertiary}
          value={prompt}
          onChangeText={setPrompt}
          multiline
          maxLength={4000}
          editable={!running && userId !== null}
        />

        <Pressable
          style={[
            styles.button,
            {
              backgroundColor: palette.accent,
              opacity: running || prompt.trim().length === 0 ? 0.5 : 1,
            },
          ]}
          onPress={onSubmit}
          disabled={running || prompt.trim().length === 0 || userId === null}
        >
          {running ? (
            <ActivityIndicator color={palette.accentInk} />
          ) : (
            <Text style={[type.bodyStrong, { color: palette.accentInk }]}>
              Run AI
            </Text>
          )}
        </Pressable>

        {error ? (
          <Text style={[type.body, styles.errorText, { color: palette.danger }]}>
            {error}
          </Text>
        ) : null}

        <Text
          style={[type.captionStrong, styles.counter, { color: palette.inkSecondary }]}
        >
          {counterText}
        </Text>

        {latest ? (
          <View
            style={[
              styles.resultCard,
              {
                backgroundColor: palette.surface,
                borderColor: palette.line,
              },
            ]}
          >
            <View style={styles.badgeRow}>
              <Text
                style={[
                  type.captionStrong,
                  styles.badge,
                  latest.stubbed
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
                {latest.stubbed ? 'STUBBED' : 'LIVE'}
              </Text>
              <Text style={[type.caption, { color: palette.inkTertiary }]}>
                {new Date(latest.createdAt).toLocaleTimeString()}
              </Text>
            </View>

            {latest.steps.map((step, i) => (
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
              {JSON.stringify({ steps: latest.steps }, null, 2)}
            </Text>

            {latest.shareId ? (
              <Pressable
                onPress={() =>
                  router.push({
                    pathname: '/result/[id]',
                    params: { id: latest.shareId },
                  })
                }
              >
                <Text
                  style={[type.bodyStrong, { color: palette.ink }]}
                >
                  Open share link →
                </Text>
              </Pressable>
            ) : null}
          </View>
        ) : (
          <Text style={[type.body, { color: palette.inkTertiary }]}>
            No runs yet. Type a prompt and tap Run AI.
          </Text>
        )}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  badge: {
    borderRadius: radius.md,
    overflow: 'hidden',
    paddingHorizontal: space.sm,
    paddingVertical: space.xs,
  },
  badgeRow: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  button: {
    alignItems: 'center',
    borderRadius: radius.lg,
    marginTop: space.md,
    paddingVertical: space.md,
  },
  container: {
    alignItems: 'center',
    padding: layout.screenPadding,
  },
  counter: {
    marginTop: space.xl,
  },
  errorBox: {
    borderRadius: radius.lg,
    borderWidth: 1,
    marginTop: space.lg,
    padding: space.md,
  },
  errorText: {
    marginTop: space.md,
  },
  input: {
    borderRadius: radius.lg,
    borderWidth: 1,
    marginTop: space.xl,
    minHeight: 96,
    padding: space.md,
    textAlignVertical: 'top',
  },
  jsonBlock: {
    borderRadius: radius.md,
    marginTop: space.md,
    padding: space.md,
  },
  resultCard: {
    borderRadius: radius.xl,
    borderWidth: 1,
    marginTop: space.md,
    padding: space.lg,
  },
  step: {
    marginTop: space.md,
  },
  subtitle: {
    marginTop: space.sm,
  },
});
