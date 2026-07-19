<script setup lang="ts">
import { ref } from 'vue'
import { login } from './authClient'

const email = ref('')
const password = ref('')

async function submit(): Promise<void> {
  await login(email.value, password.value)
}
</script>

<template>
  <form aria-label="Login" @submit.prevent="submit">
    <input v-model="email" type="email">
    <input v-model="password" type="password">
    <button type="submit">Login</button>
  </form>
</template>
