import axios from 'axios'

const api = axios.create({ baseURL: '/api' })

api.interceptors.request.use((config) => {
  const t = localStorage.getItem('boxion_token')
  if (t) config.headers.Authorization = `Bearer ${t}`
  return config
})

export default api
