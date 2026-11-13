// eslint.config.js — flat config for eslint-config-expo (SDK 58).
// https://docs.expo.dev/guides/using-eslint/
const { defineConfig } = require('eslint/config');
const expoConfig = require('eslint-config-expo/flat');

module.exports = defineConfig(expoConfig);
