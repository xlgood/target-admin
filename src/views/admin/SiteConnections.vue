<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { adminAPI } from '@/api/admin'
import { useAdminAuthStore } from '@/stores/auth'
import type { AdminProviderBalanceSnapshot, AdminProviderCatalogSyncRun, AdminSiteConnection, ProviderCatalogContentSyncResult, ProviderCatalogSyncResult } from '@/api/types'
import IdCell from '@/components/IdCell.vue'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Dialog, DialogScrollContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import TableSkeleton from '@/components/TableSkeleton.vue'
import ListPagination from '@/components/ListPagination.vue'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { confirmAction } from '@/utils/confirm'
import { notifyError, notifyInfo, notifySuccess } from '@/utils/notify'
import { useFormValidation, rules } from '@/composables/useFormValidation'

const { t } = useI18n()
const authStore = useAdminAuthStore()
const loading = ref(true)
const connections = ref<AdminSiteConnection[]>([])
const pagination = reactive({
  page: 1,
  page_size: 20,
  total: 0,
  total_page: 1,
})
const showModal = ref(false)
const isEditing = ref(false)
const editingId = ref<number | null>(null)
const pingingId = ref<number | null>(null)
const syncingProviderCatalog = ref(false)
const syncingProviderCatalogContent = ref(false)
const showBalanceHistory = ref(false)
const balanceHistoryConnection = ref<AdminSiteConnection | null>(null)
const balanceSnapshots = ref<AdminProviderBalanceSnapshot[]>([])
const balanceHistoryLoading = ref(false)
const showCatalogHistory = ref(false)
const catalogSyncRuns = ref<AdminProviderCatalogSyncRun[]>([])
const catalogHistoryLoading = ref(false)

const form = reactive({
  name: '',
  base_url: '',
  api_key: '',
  api_secret: '',
  protocol: 'dujiao-next',
  callback_url: '',
  retry_max: 3,
  retry_intervals: '30,60,120',
  exchange_rate: 1,
  price_markup_percent: 0,
  price_rounding_mode: 'none',
  auto_sync_price: 'false',
  balance_alert_minimum: 0,
})
const canSyncProviderCatalog = computed(() => authStore.hasPermission('POST:/admin/provider-catalog/sync'))

const siteConnectionSchema = {
  name: [rules.required()],
  base_url: [rules.required(), rules.url()],
  api_key: [rules.required()],
}
const { errors, validate, clearErrors } = useFormValidation(siteConnectionSchema)

const fetchConnections = async (page = 1) => {
  loading.value = true
  try {
    const res = await adminAPI.getSiteConnections({
      page,
      page_size: pagination.page_size,
    })
    connections.value = res.data.data || []
    const p = res.data.pagination
    if (p) {
      pagination.page = p.page
      pagination.page_size = p.page_size
      pagination.total = p.total
      pagination.total_page = p.total_page
    }
  } catch {
    connections.value = []
  } finally {
    loading.value = false
  }
}

const changePage = (page: number) => {
  if (page < 1 || page > pagination.total_page) return
  fetchConnections(page)
}

const pageSizeOptions = [10, 20, 50, 100]

const changePageSize = (size: number) => {
  if (size === pagination.page_size) return
  pagination.page_size = size
  fetchConnections(1)
}

const resetForm = () => {
  Object.assign(form, {
    name: '',
    base_url: '',
    api_key: '',
    api_secret: '',
    protocol: 'dujiao-next',
    callback_url: '',
    retry_max: 3,
    retry_intervals: '30,60,120',
    exchange_rate: 1,
    price_markup_percent: 0,
    price_rounding_mode: 'none',
    auto_sync_price: 'false',
    balance_alert_minimum: 0,
  })
}

const openCreateModal = () => {
  isEditing.value = false
  editingId.value = null
  clearErrors()
  resetForm()
  showModal.value = true
}

const openEditModal = (conn: AdminSiteConnection) => {
  isEditing.value = true
  editingId.value = conn.id
  Object.assign(form, {
    name: conn.name || '',
    base_url: conn.base_url || '',
    api_key: conn.api_key || '',
    api_secret: conn.api_secret || '',
    protocol: conn.protocol || 'dujiao-next',
    callback_url: conn.callback_url || '',
    retry_max: conn.retry_max ?? 3,
    retry_intervals: (() => {
      const ri = conn.retry_intervals
      if (Array.isArray(ri)) return ri.join(',')
      if (typeof ri === 'string') {
        try {
          const parsed = JSON.parse(ri)
          if (Array.isArray(parsed)) return parsed.join(',')
        } catch { /* ignore */ }
        return ri
      }
      return '30,60,120'
    })(),
    exchange_rate: conn.exchange_rate ?? 1,
    price_markup_percent: conn.price_markup_percent ?? 0,
    price_rounding_mode: conn.price_rounding_mode || 'none',
    auto_sync_price: conn.auto_sync_price ? 'true' : 'false',
    balance_alert_minimum: conn.balance_alert_minimum ?? 0,
  })
  showModal.value = true
}

const closeModal = () => {
  showModal.value = false
  clearErrors()
}

const buildPayload = () => {
  const intervals = form.retry_intervals
    .split(',')
    .map((s: string) => Number(s.trim()))
    .filter((n: number) => !Number.isNaN(n) && n > 0)
  return {
    name: form.name,
    base_url: form.base_url,
    api_key: form.api_key,
    api_secret: form.api_secret,
    protocol: form.protocol,
    callback_url: form.callback_url,
    retry_max: Number(form.retry_max) || 3,
    retry_intervals: JSON.stringify(intervals),
    exchange_rate: Number(form.exchange_rate) || 1,
    price_markup_percent: Number(form.price_markup_percent) || 0,
    price_rounding_mode: form.price_rounding_mode,
    auto_sync_price: form.auto_sync_price === 'true',
    balance_alert_minimum: Number(form.balance_alert_minimum) || 0,
  }
}

const handleSubmit = async () => {
  if (!validate({ ...form } as Record<string, unknown>)) return
  try {
    const payload = buildPayload()
    if (isEditing.value && editingId.value) {
      await adminAPI.updateSiteConnection(editingId.value, payload)
    } else {
      await adminAPI.createSiteConnection(payload)
    }
    closeModal()
    fetchConnections(isEditing.value ? pagination.page : 1)
    notifySuccess()
  } catch (err: any) {
    notifyError(err?.response?.data?.message || err?.message)
  }
}

const handlePing = async (conn: AdminSiteConnection) => {
  pingingId.value = conn.id
  try {
    await adminAPI.pingSiteConnection(conn.id)
    notifySuccess(t('siteConnections.ping.success'))
    fetchConnections(pagination.page)
  } catch (err: any) {
    notifyError(t('siteConnections.ping.failed') + ': ' + (err?.response?.data?.message || err?.message || ''))
  } finally {
    pingingId.value = null
  }
}

const handleToggleStatus = async (conn: AdminSiteConnection) => {
  const nextStatus = conn.status === 'active' ? 'disabled' : 'active'
  try {
    await adminAPI.updateSiteConnectionStatus(conn.id, { status: nextStatus })
    fetchConnections(pagination.page)
    notifySuccess()
  } catch (err: any) {
    notifyError(err?.response?.data?.message || err?.message)
  }
}

const handleDelete = async (conn: AdminSiteConnection) => {
  const confirmed = await confirmAction({
    description: t('siteConnections.delete.confirm', { name: conn.name || '#' + conn.id }),
    confirmText: t('admin.common.delete'),
    variant: 'destructive',
  })
  if (!confirmed) return
  try {
    await adminAPI.deleteSiteConnection(conn.id)
    fetchConnections(pagination.page)
    notifySuccess()
  } catch (err: any) {
    notifyError(err?.response?.data?.message || err?.message)
  }
}

const findConnectionByProtocol = (protocol: string) => {
  return connections.value.find((conn) => conn.protocol === protocol)
}

const handleSyncProviderCatalog = async () => {
  const fansConn = findConnectionByProtocol('fansgurus')
  const tgxConn = findConnectionByProtocol('tgx-account')
  if (!fansConn || !tgxConn) {
    notifyError(t('siteConnections.providerCatalog.missingConnections'))
    return
  }

  const confirmed = await confirmAction({
    description: t('siteConnections.providerCatalog.confirm', {
      fans: fansConn.name || `#${fansConn.id}`,
      tgx: tgxConn.name || `#${tgxConn.id}`,
    }),
    confirmText: t('siteConnections.providerCatalog.action'),
  })
  if (!confirmed) return

  syncingProviderCatalog.value = true
  try {
    const res = await adminAPI.syncProviderCatalog({
      fansgurus_connection_id: fansConn.id,
      tgx_connection_id: tgxConn.id,
    })
    const result = res.data.data as ProviderCatalogSyncResult | undefined
    notifySuccess(t('siteConnections.providerCatalog.success', {
      pulled: (result?.fans_gurus_pulled ?? 0) + (result?.tgx_pulled ?? 0),
      imported: result?.imported ?? 0,
      updated: result?.updated ?? 0,
      skipped: result?.skipped ?? 0,
      filtered: (result?.filtered_telegram ?? 0) + (result?.filtered_inactive ?? 0) + (result?.filtered_platform ?? 0),
      deactivated: result?.deactivated ?? 0,
    }))
    if (result && !result.inventory_refresh_queued) {
      notifyInfo(t(`siteConnections.providerCatalog.inventoryRefresh.${result.inventory_refresh_status}`))
    }
    fetchConnections(pagination.page)
  } catch (err: any) {
    notifyError(err?.response?.data?.message || err?.message)
  } finally {
    syncingProviderCatalog.value = false
  }
}

const handleSyncProviderCatalogContent = async () => {
  const fansConn = findConnectionByProtocol('fansgurus')
  const tgxConn = findConnectionByProtocol('tgx-account')
  if (!fansConn || !tgxConn) {
    notifyError(t('siteConnections.providerCatalog.missingConnections'))
    return
  }
  const confirmed = await confirmAction({
    description: t('siteConnections.providerCatalog.contentConfirm'),
    confirmText: t('siteConnections.providerCatalog.contentAction'),
  })
  if (!confirmed) return
  syncingProviderCatalogContent.value = true
  try {
    const res = await adminAPI.syncProviderCatalogContent({
      fansgurus_connection_id: fansConn.id,
      tgx_connection_id: tgxConn.id,
    })
    const data = res.data.data
    if (data?.status === 'queued') {
      notifySuccess(t('siteConnections.providerCatalog.contentQueued'))
      return
    }
    if (data?.status === 'queue_disabled') {
      notifyInfo(t('siteConnections.providerCatalog.contentQueueDisabled'))
      return
    }
    const result = data as ProviderCatalogContentSyncResult | undefined
    notifySuccess(t('siteConnections.providerCatalog.contentSuccess', {
      pulled: (result?.fans_gurus_pulled ?? 0) + (result?.tgx_pulled ?? 0),
      matched: result?.matched ?? 0,
      updated: result?.updated ?? 0,
      skipped: result?.skipped ?? 0,
    }))
  } catch (err: any) {
    notifyError(err?.response?.data?.message || err?.message)
  } finally {
    syncingProviderCatalogContent.value = false
  }
}

const openBalanceHistory = async (connection: AdminSiteConnection) => {
  balanceHistoryConnection.value = connection
  showBalanceHistory.value = true
  balanceHistoryLoading.value = true
  try {
    const res = await adminAPI.getProviderBalanceSnapshots({ connection_id: connection.id, page: 1, page_size: 50 })
    balanceSnapshots.value = (res.data.data as AdminProviderBalanceSnapshot[]) || []
  } catch {
    balanceSnapshots.value = []
  } finally {
    balanceHistoryLoading.value = false
  }
}

const openCatalogHistory = async () => {
  showCatalogHistory.value = true
  catalogHistoryLoading.value = true
  try {
    const res = await adminAPI.getProviderCatalogSyncRuns({ page: 1, page_size: 30 })
    catalogSyncRuns.value = (res.data.data as AdminProviderCatalogSyncRun[]) || []
  } catch {
    catalogSyncRuns.value = []
  } finally {
    catalogHistoryLoading.value = false
  }
}

const downloadCatalogReasons = async (run: AdminProviderCatalogSyncRun) => {
  try {
    const res = await adminAPI.exportProviderCatalogFilterReasons(run.id)
    const url = URL.createObjectURL(res.data as Blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `provider-catalog-filter-reasons-${run.id}.csv`
    link.click()
    URL.revokeObjectURL(url)
  } catch (err: any) {
    notifyError(err?.response?.data?.message || err?.message)
  }
}

const statusBadgeClass = (status?: string) => {
  switch (status) {
    case 'active':
      return 'text-emerald-700 border-emerald-200 bg-emerald-50'
    case 'pending':
      return 'text-yellow-700 border-yellow-200 bg-yellow-50'
    default:
      return 'text-muted-foreground border-border bg-muted/30'
  }
}

const statusLabel = (status?: string) => {
  const key = `siteConnections.status.${status}`
  const translated = t(key)
  return translated !== key ? translated : status
}

const formatTime = (raw?: string) => {
  if (!raw) return '-'
  const d = new Date(raw)
  if (Number.isNaN(d.getTime())) return '-'
  return d.toLocaleString()
}

onMounted(() => {
  fetchConnections()
})
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <h1 class="text-2xl font-semibold">{{ t('siteConnections.title') }}</h1>
      <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
        <Button
          v-if="canSyncProviderCatalog"
          variant="outline"
          class="w-full sm:w-auto"
          :disabled="loading || syncingProviderCatalog"
          @click="handleSyncProviderCatalog"
        >
          {{ syncingProviderCatalog ? t('siteConnections.providerCatalog.syncing') : t('siteConnections.providerCatalog.action') }}
        </Button>
		<Button
			v-if="canSyncProviderCatalog"
			variant="outline"
			class="w-full sm:w-auto"
			:disabled="loading || syncingProviderCatalogContent"
			@click="handleSyncProviderCatalogContent"
		>
			{{ syncingProviderCatalogContent ? t('siteConnections.providerCatalog.contentSyncing') : t('siteConnections.providerCatalog.contentAction') }}
		</Button>
				<Button v-if="canSyncProviderCatalog" variant="outline" class="w-full sm:w-auto" @click="openCatalogHistory">目录同步历史</Button>
        <Button class="w-full sm:w-auto" @click="openCreateModal">{{ t('siteConnections.createButton') }}</Button>
      </div>
    </div>

    <div class="rounded-xl border border-border bg-card overflow-x-auto">
      <Table class="min-w-[900px]">
        <TableHeader class="border-b border-border bg-muted/40 text-xs uppercase text-muted-foreground">
          <TableRow>
            <TableHead class="px-6 py-3">{{ t('siteConnections.columns.id') }}</TableHead>
            <TableHead class="min-w-[160px] px-6 py-3">{{ t('siteConnections.columns.name') }}</TableHead>
            <TableHead class="min-w-[200px] px-6 py-3">{{ t('siteConnections.columns.baseUrl') }}</TableHead>
            <TableHead class="min-w-[80px] px-6 py-3">{{ t('siteConnections.columns.protocol') }}</TableHead>
            <TableHead class="min-w-[80px] px-6 py-3">{{ t('siteConnections.columns.markup') }}</TableHead>
            <TableHead class="min-w-[90px] px-6 py-3">{{ t('siteConnections.columns.status') }}</TableHead>
            <TableHead class="min-w-[80px] px-6 py-3">{{ t('siteConnections.columns.lastPing') }}</TableHead>
            <TableHead class="min-w-[200px] px-6 py-3 text-right">{{ t('siteConnections.columns.actions') }}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody class="divide-y divide-border">
          <TableRow v-if="loading">
            <TableCell :colspan="8" class="p-0">
              <TableSkeleton :columns="8" :rows="5" />
            </TableCell>
          </TableRow>
          <TableRow v-else-if="connections.length === 0">
            <TableCell colspan="8" class="px-6 py-8 text-center text-muted-foreground">{{ t('siteConnections.empty') }}</TableCell>
          </TableRow>
          <TableRow v-for="conn in connections" :key="conn.id" class="hover:bg-muted/30">
            <TableCell class="px-6 py-4">
              <IdCell :value="conn.id" />
            </TableCell>
            <TableCell class="min-w-[160px] px-6 py-4 font-medium text-foreground break-words">{{ conn.name }}</TableCell>
            <TableCell class="min-w-[200px] px-6 py-4 text-xs text-muted-foreground font-mono break-all">{{ conn.base_url }}</TableCell>
            <TableCell class="min-w-[80px] px-6 py-4 text-xs text-muted-foreground break-words">{{ conn.protocol }}</TableCell>
            <TableCell class="min-w-[110px] px-6 py-4 text-xs text-muted-foreground">
              <span v-if="conn.price_markup_percent && Number(conn.price_markup_percent) !== 0" class="inline-flex rounded-full border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs text-blue-700">
                +{{ conn.price_markup_percent }}%
              </span>
              <span v-else class="text-muted-foreground">-</span>
              <div v-if="conn.last_balance" class="mt-1 font-mono text-foreground">
                {{ conn.last_balance }} {{ conn.last_balance_currency || '' }}
              </div>
            </TableCell>
            <TableCell class="min-w-[90px] px-6 py-4">
              <span
                class="inline-flex rounded-full border px-2.5 py-1 text-xs"
                :class="statusBadgeClass(conn.status)"
              >
                {{ statusLabel(conn.status) }}
              </span>
            </TableCell>
            <TableCell class="min-w-[80px] px-6 py-4 text-xs text-muted-foreground">{{ formatTime(conn.last_ping_at) }}</TableCell>
            <TableCell class="min-w-[160px] px-6 py-4 text-right">
              <div class="flex flex-wrap items-center justify-end gap-2">
                <Button size="sm" variant="outline" @click="openEditModal(conn)">{{ t('admin.common.edit') }}</Button>
                <Button
                  size="sm"
                  variant="outline"
                  :disabled="pingingId === conn.id"
                  @click="handlePing(conn)"
                >
                  {{ pingingId === conn.id ? t('siteConnections.ping.loading') : 'Ping' }}
                </Button>
						<Button v-if="conn.protocol === 'fansgurus' || conn.protocol === 'tgx-account'" size="sm" variant="outline" @click="openBalanceHistory(conn)">余额历史</Button>
                <Button size="sm" variant="outline" @click="handleToggleStatus(conn)">
                  {{ conn.status === 'active' ? t('siteConnections.actions.disable') : t('siteConnections.actions.enable') }}
                </Button>
                <Button size="sm" variant="destructive" @click="handleDelete(conn)">{{ t('admin.common.delete') }}</Button>
              </div>
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>

      <ListPagination
        :page="pagination.page"
        :total-page="pagination.total_page"
        :total="pagination.total"
        :page-size="pagination.page_size"
        :page-size-options="pageSizeOptions"
        @change-page="changePage"
        @change-page-size="changePageSize"
      />
    </div>

		<Dialog v-model:open="showBalanceHistory">
			<DialogScrollContent class="w-[calc(100vw-1rem)] max-w-3xl p-4 sm:p-6">
				<DialogHeader><DialogTitle>{{ balanceHistoryConnection?.name || '上游' }}余额历史</DialogTitle></DialogHeader>
				<div v-if="balanceHistoryLoading" class="py-8 text-center text-sm text-muted-foreground">加载中...</div>
				<div v-else class="max-h-[65vh] overflow-auto rounded border"><Table class="min-w-[680px]"><TableHeader><TableRow><TableHead>检查时间</TableHead><TableHead>状态</TableHead><TableHead>余额</TableHead><TableHead>告警</TableHead><TableHead>错误</TableHead></TableRow></TableHeader><TableBody><TableRow v-for="snapshot in balanceSnapshots" :key="snapshot.id"><TableCell>{{ formatTime(snapshot.checked_at) }}</TableCell><TableCell>{{ snapshot.status }}</TableCell><TableCell>{{ snapshot.balance }} {{ snapshot.currency }}</TableCell><TableCell>{{ snapshot.alert_status || '-' }}</TableCell><TableCell class="max-w-[240px] break-words">{{ snapshot.error_message || '-' }}</TableCell></TableRow><TableRow v-if="balanceSnapshots.length === 0"><TableCell colspan="5" class="py-8 text-center text-muted-foreground">暂无记录</TableCell></TableRow></TableBody></Table></div>
			</DialogScrollContent>
		</Dialog>

		<Dialog v-model:open="showCatalogHistory">
			<DialogScrollContent class="w-[calc(100vw-1rem)] max-w-5xl p-4 sm:p-6">
				<DialogHeader><DialogTitle>上游目录同步历史</DialogTitle></DialogHeader>
				<div v-if="catalogHistoryLoading" class="py-8 text-center text-sm text-muted-foreground">加载中...</div>
				<div v-else class="max-h-[65vh] overflow-auto rounded border"><Table class="min-w-[900px]"><TableHeader><TableRow><TableHead>时间</TableHead><TableHead>状态</TableHead><TableHead>拉取</TableHead><TableHead>导入/更新</TableHead><TableHead>筛除</TableHead><TableHead class="text-right">操作</TableHead></TableRow></TableHeader><TableBody><TableRow v-for="run in catalogSyncRuns" :key="run.id"><TableCell>{{ formatTime(run.finished_at) }}</TableCell><TableCell>{{ run.status }}</TableCell><TableCell>Fans {{ run.fansgurus_pulled }} / TGX {{ run.tgx_pulled }}</TableCell><TableCell>{{ run.imported }} / {{ run.updated }}</TableCell><TableCell><div>{{ run.filtered_telegram + run.filtered_inactive + run.filtered_platform }}</div><div class="text-xs text-muted-foreground">Telegram {{ run.filtered_telegram }} / 非活跃 {{ run.filtered_inactive }} / 平台 {{ run.filtered_platform }}</div></TableCell><TableCell class="text-right"><Button size="sm" variant="outline" @click="downloadCatalogReasons(run)">导出筛选原因</Button></TableCell></TableRow><TableRow v-if="catalogSyncRuns.length === 0"><TableCell colspan="6" class="py-8 text-center text-muted-foreground">暂无记录</TableCell></TableRow></TableBody></Table></div>
			</DialogScrollContent>
		</Dialog>

    <Dialog v-model:open="showModal" @update:open="(value: boolean) => { if (!value) closeModal() }">
      <DialogScrollContent class="w-[calc(100vw-1rem)] max-w-2xl p-4 sm:p-6" @interact-outside="(e: Event) => e.preventDefault()">
        <DialogHeader>
          <DialogTitle>{{ isEditing ? t('siteConnections.editTitle') : t('siteConnections.createTitle') }}</DialogTitle>
        </DialogHeader>

        <form class="space-y-6" @submit.prevent="handleSubmit">
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div class="md:col-span-2">
              <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.name') }}</label>
              <Input v-model="form.name" required :placeholder="t('siteConnections.form.namePlaceholder')" />
              <p v-if="errors.name" class="text-xs text-destructive mt-1">{{ errors.name }}</p>
            </div>
            <div class="md:col-span-2">
              <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.baseUrl') }}</label>
              <Input v-model="form.base_url" required :placeholder="t('siteConnections.form.baseUrlPlaceholder')" />
              <p v-if="errors.base_url" class="text-xs text-destructive mt-1">{{ errors.base_url }}</p>
            </div>
            <div>
              <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.apiKey') }}</label>
              <Input v-model="form.api_key" :placeholder="t('siteConnections.form.apiKeyPlaceholder')" />
              <p v-if="errors.api_key" class="text-xs text-destructive mt-1">{{ errors.api_key }}</p>
            </div>
            <div>
              <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.apiSecret') }}</label>
              <Input v-model="form.api_secret" type="password" :placeholder="t('siteConnections.form.apiSecretPlaceholder')" />
            </div>
            <div>
              <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.protocol') }}</label>
              <Select v-model="form.protocol">
                <SelectTrigger class="h-9 w-full">
                  <SelectValue :placeholder="t('siteConnections.form.protocolPlaceholder')" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="dujiao-next">dujiao-next</SelectItem>
                  <SelectItem value="fansgurus">fansgurus</SelectItem>
                  <SelectItem value="tgx-account">tgx-account</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.callbackUrl') }}</label>
              <Input v-model="form.callback_url" :placeholder="t('siteConnections.form.callbackUrlPlaceholder')" />
            </div>
            <div>
              <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.retryMax') }}</label>
              <Input v-model.number="form.retry_max" type="number" min="0" placeholder="3" />
            </div>
            <div>
              <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.retryIntervals') }}</label>
              <Input v-model="form.retry_intervals" placeholder="30,60,120" />
            </div>
          </div>

          <div class="border-t border-border pt-4">
            <h3 class="mb-3 text-sm font-medium text-foreground">{{ t('siteConnections.form.markupSection') }}</h3>
            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div>
                <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.exchangeRate') }}</label>
                <Input v-model.number="form.exchange_rate" type="number" step="0.000001" min="0" placeholder="1" />
                <p class="mt-1 text-xs text-muted-foreground">{{ t('siteConnections.form.exchangeRateHint') }}</p>
              </div>
              <div>
                <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.priceMarkupPercent') }}</label>
                <div class="relative">
                  <Input v-model.number="form.price_markup_percent" type="number" step="0.01" min="0" placeholder="0" />
                  <span class="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">%</span>
                </div>
                <p class="mt-1 text-xs text-muted-foreground">{{ t('siteConnections.form.priceMarkupPercentHint') }}</p>
              </div>
              <div>
                <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.priceRoundingMode') }}</label>
                <Select v-model="form.price_rounding_mode">
                  <SelectTrigger class="h-9 w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">{{ t('siteConnections.form.roundingNone') }}</SelectItem>
                    <SelectItem value="ceil_int">{{ t('siteConnections.form.roundingCeilInt') }}</SelectItem>
                    <SelectItem value="ceil_tenth">{{ t('siteConnections.form.roundingCeilTenth') }}</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div>
                <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.autoSyncPrice') }}</label>
                <Select v-model="form.auto_sync_price">
                  <SelectTrigger class="h-9 w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="false">{{ t('admin.common.no') }}</SelectItem>
                    <SelectItem value="true">{{ t('admin.common.yes') }}</SelectItem>
                  </SelectContent>
                </Select>
                <p class="mt-1 text-xs text-muted-foreground">{{ t('siteConnections.form.autoSyncPriceHint') }}</p>
              </div>
              <div>
                <label class="mb-1.5 block text-xs font-medium text-muted-foreground">{{ t('siteConnections.form.balanceAlertMinimum') }}</label>
                <Input v-model.number="form.balance_alert_minimum" type="number" step="0.01" min="0" placeholder="0" />
                <p class="mt-1 text-xs text-muted-foreground">{{ t('siteConnections.form.balanceAlertMinimumHint') }}</p>
              </div>
            </div>
          </div>

          <div class="flex flex-col-reverse gap-3 border-t border-border pt-6 sm:flex-row sm:justify-end">
            <Button type="button" variant="outline" class="w-full sm:w-auto" @click="closeModal">{{ t('admin.common.cancel') }}</Button>
            <Button type="submit" class="w-full sm:w-auto">{{ isEditing ? t('admin.common.save') : t('admin.common.create') }}</Button>
          </div>
        </form>
      </DialogScrollContent>
    </Dialog>
  </div>
</template>
