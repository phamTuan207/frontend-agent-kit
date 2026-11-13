// app/(tabs)/_layout.tsx — two tabs: Home + one placeholder tab.
// Icons use Ionicons (@expo/vector-icons): visible on Android, unlike
// expo-symbols (iOS-only). No native modules beyond the Expo Go set.
import { Ionicons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';

import { colors } from '../../theme';
import { useColorScheme } from 'react-native';

export default function TabLayout() {
  const scheme = useColorScheme() ?? 'light';
  const palette = colors[scheme];

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: palette.ink,
        tabBarInactiveTintColor: palette.inkTertiary,
        tabBarStyle: { backgroundColor: palette.background },
        headerStyle: { backgroundColor: palette.background },
        headerTintColor: palette.ink,
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Home',
          tabBarIcon: ({ color, size }) => (
            <Ionicons
              name="home-outline"
              // RN 0.88 types tabBarIcon's color as ____ColorValue_Internal
              // (string | number | NativeColorValue | null); Ionicons
              // wants string | NativeColorValue. Navigation always
              // passes a string at runtime; non-strings fall back.
              color={typeof color === 'string' ? color : undefined}
              size={size}
            />
          ),
        }}
      />
      <Tabs.Screen
        name="more"
        options={{
          title: 'More',
          tabBarIcon: ({ color, size }) => (
            <Ionicons
              name="ellipsis-horizontal"
              // See home tab above: nullable ____ColorValue_Internal.
              color={typeof color === 'string' ? color : undefined}
              size={size}
            />
          ),
        }}
      />
    </Tabs>
  );
}
