<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { adminAPI } from '@/api/admin'
import type { AdminResellerDomain, AdminResellerProfileDetail } from '@/api/types'
import {
  RESELLER_DOMAIN_STATUS_ACTIVE,
  RESELLER_DOMAIN_TYPE_CUSTOM,
  RESELLER_DOMAIN_TYPE_SUBDOMAIN,
  RESELLER_DOMAIN_VERIFICATION_VERIFIED,
  RESELLER_PROFILE_STATUS_ACTIVE,
  RESELLER_PROFILE_STATUS_DISABLED,
  RESELLER_PROFILE_STATUS_PENDING_REVIEW,
  RESELLER_PROFILE_STATUS_REJECTED,
  RESELLER_SETTLEMENT_STATUS_FROZEN,
  RESELLER_SETTLEMENT_STATUS_NORMAL,
} from '@/constants/reseller'
import { Button } from '@/components/ui/button'
import { Dialog, DialogHeader, DialogScrollContent, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { confirmAction } from '@/utils/confirm'
import { formatDate, formatMoney, getLocalizedText } from '@/utils/format'
import { notifyError, notifySuccess } from '@/utils/notify'
import { getResellerProfileStatusKey } from '@/utils/resellerManagement'

const route = useRoute()
const router = useRouter()
const adminPath = import.meta.env.VITE_ADMIN_PATH || ''

const loading = ref(true)
const saving = ref(false)
const savingSystemDomain = ref(false)
const operatingDomainId = ref<number | null>(null)
const detail = ref<AdminResellerProfileDetail | null>(null)
const currentTab = ref('overview')
const showEditDialog = ref(false)

const profileId = computed(() => Number(route.params.id || 0))
const profile = computed(() => detail.value?.profile || null)
const domains = computed(() => detail.value?.domains || [])
const isActiveVerifiedDomain = (item: AdminResellerDomain) =>
  item.status === RESELLER_DOMAIN_STATUS_ACTIVE &&
  item.verification_status === RESELLER_DOMAIN_VERIFICATION_VERIFIED
const activeVerifiedDomains = computed(() =>
  domains.value.filter(isActiveVerifiedDomain),
)
const primaryDomain = computed(() => activeVerifiedDomains.value.find((item) => item.is_primary) || null)
const systemDomain = computed(() => domains.value.find((item) => item.type === RESELLER_DOMAIN_TYPE_SUBDOMAIN) || null)

const editForm = reactive({
  defaultMarkup: '0.00',
  maxMarkup: '0.00',
  settlementStatus: RESELLER_SETTLEMENT_STATUS_NORMAL,
  reason: '',
})

const systemDomainForm = reactive({
  subdomain: '',
})

const syncSystemDomainForm = () => {
  systemDomainForm.subdomain = systemDomain.value?.domain || ''
}

const fetchDetail = async () => {
  if (!profileId.value) return
  loading.value = true
  try {
    const response = await adminAPI.getResellerProfile(profileId.value)
    detail.value = response.data.data as AdminResellerProfileDetail
    syncSystemDomainForm()
  } catch (err: any) {
    detail.value = null
    notifyError(err?.message || '加载分销商详情失败')
  } finally {
    loading.value = false
  }
}

const openEditDialog = () => {
  if (!profile.value) return
  editForm.defaultMarkup = profile.value.default_markup_percent || '0.00'
  editForm.maxMarkup = profile.value.max_markup_percent || '0.00'
  editForm.settlementStatus = profile.value.settlement_status || RESELLER_SETTLEMENT_STATUS_NORMAL
  editForm.reason = ''
  showEditDialog.value = true
}

const validateMarkupRange = (defaultMarkup: string, maxMarkup: string) => {
  const defaultValue = Number(defaultMarkup.trim() || '0')
  const maxValue = Number(maxMarkup.trim() || '0')
  if (!Number.isFinite(defaultValue) || !Number.isFinite(maxValue) || defaultValue < 0 || maxValue < 0) {
    notifyError('加价比例必须是大于或等于 0 的数字')
    return false
  }
  if (maxValue > 0 && defaultValue > maxValue) {
    notifyError('默认加价比例不能大于封顶加价比例')
    return false
  }
  return true
}

const submitEditProfile = async () => {
  if (!profile.value) return
  if (!validateMarkupRange(editForm.defaultMarkup, editForm.maxMarkup)) return
  saving.value = true
  try {
    await adminAPI.updateResellerProfile(profile.value.id, {
      default_markup_percent: editForm.defaultMarkup.trim() || '0.00',
      max_markup_percent: editForm.maxMarkup.trim() || '0.00',
      settlement_status: editForm.settlementStatus,
      reason: editForm.reason.trim() || undefined,
    })
    showEditDialog.value = false
    notifySuccess('分销商运营配置已保存')
    await fetchDetail()
  } catch (err: any) {
    notifyError(err?.message || '保存分销商运营配置失败')
  } finally {
    saving.value = false
  }
}

const submitSystemDomain = async () => {
  if (!profile.value) return
  const raw = systemDomainForm.subdomain.trim()
  if (!raw) {
    notifyError('请输入系统二级域名前缀或完整域名')
    return
  }
  savingSystemDomain.value = true
  try {
    await adminAPI.assignResellerSystemDomain(profile.value.id, { subdomain: raw })
    notifySuccess('系统二级域名已保存')
    await fetchDetail()
  } catch (err: any) {
    notifyError(err?.message || '保存系统二级域名失败')
  } finally {
    savingSystemDomain.value = false
  }
}

const setPrimaryDomain = async (domain: AdminResellerDomain) => {
  if (domain.is_primary) return
  const confirmed = await confirmAction({ description: `确认将 ${domain.domain} 设为 R#${domain.reseller_id} 的主域名？` })
  if (!confirmed) return
  operatingDomainId.value = domain.id
  try {
    await adminAPI.setPrimaryResellerDomain(domain.id)
    notifySuccess('主域名已更新')
    await fetchDetail()
  } catch (err: any) {
    notifyError(err?.message || '设置主域名失败')
  } finally {
    operatingDomainId.value = null
  }
}

const canSetPrimary = (domain: AdminResellerDomain) =>
  !domain.is_primary &&
  isActiveVerifiedDomain(domain)

const statusLabel = (status?: string) => {
  const key = getResellerProfileStatusKey(status)
  const map: Record<string, string> = {
    pendingReview: '待审核',
    active: '已启用',
    rejected: '已拒绝',
    disabled: '已禁用',
    unknown: '未知',
  }
  return map[key] || status || '-'
}

const statusClass = (status?: string) => {
  if (status === RESELLER_PROFILE_STATUS_PENDING_REVIEW) return 'border-amber-200 bg-amber-50 text-amber-700'
  if (status === RESELLER_PROFILE_STATUS_ACTIVE) return 'border-emerald-200 bg-emerald-50 text-emerald-700'
  if (status === RESELLER_PROFILE_STATUS_REJECTED) return 'border-rose-200 bg-rose-50 text-rose-700'
  if (status === RESELLER_PROFILE_STATUS_DISABLED) return 'border-zinc-200 bg-zinc-50 text-zinc-700'
  return 'border-border bg-muted/30 text-muted-foreground'
}

const settlementLabel = (status?: string) => {
  if (status === RESELLER_SETTLEMENT_STATUS_NORMAL) return '正常'
  if (status === RESELLER_SETTLEMENT_STATUS_FROZEN) return '结算冻结'
  return status || '-'
}

const settlementClass = (status?: string) => {
  if (status === RESELLER_SETTLEMENT_STATUS_NORMAL) return 'border-emerald-200 bg-emerald-50 text-emerald-700'
  if (status === RESELLER_SETTLEMENT_STATUS_FROZEN) return 'border-amber-200 bg-amber-50 text-amber-700'
  return 'border-border bg-muted/30 text-muted-foreground'
}

const domainStatusLabel = (status?: string) => {
  if (status === 'pending_review') return '待审核'
  if (status === 'active') return '已启用'
  if (status === 'disabled') return '已禁用'
  return status || '-'
}

const domainTypeLabel = (type?: string) => {
  if (type === RESELLER_DOMAIN_TYPE_SUBDOMAIN) return '系统二级域名'
  if (type === RESELLER_DOMAIN_TYPE_CUSTOM) return '自定义域名'
  return type || '-'
}

const verificationLabel = (status?: string) => {
  if (status === 'pending') return '待验证'
  if (status === 'verified') return '已验证'
  if (status === 'failed') return '验证失败'
  return status || '-'
}

const userDetailLink = computed(() => (profile.value?.user_id ? `${adminPath}/users/${profile.value.user_id}` : ''))
const siteConfigLink = computed(() => `${adminPath}/resellers/site-configs?reseller_id=${profileId.value}`)
const productSettingsLink = computed(() => `${adminPath}/resellers/product-settings?reseller_id=${profileId.value}`)
const ledgerLink = computed(() => `${adminPath}/resellers/ledger-entries?reseller_id=${profileId.value}`)
const withdrawLink = computed(() => `${adminPath}/resellers/withdraws?reseller_id=${profileId.value}`)

onMounted(fetchDetail)
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
      <div>
        <div class="mb-2 flex flex-wrap items-center gap-2">
          <Button size="sm" variant="outline" @click="router.back()">返回</Button>
          <span class="font-mono text-xs text-muted-foreground">R#{{ profileId }}</span>
        </div>
        <h1 class="text-2xl font-semibold">分销商详情</h1>
        <p class="mt-1 text-sm text-muted-foreground">
          {{ profile?.user?.display_name || profile?.user?.email || '加载中' }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button variant="outline" :disabled="loading" @click="fetchDetail">刷新</Button>
        <Button :disabled="!profile" @click="openEditDialog">编辑运营配置</Button>
      </div>
    </div>

    <div v-if="loading" class="rounded-xl border border-border bg-card p-6 text-sm text-muted-foreground">加载中...</div>
    <div v-else-if="!detail || !profile" class="rounded-xl border border-border bg-card p-6 text-sm text-muted-foreground">未找到分销商资料。</div>
    <template v-else>
      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="text-xs text-muted-foreground">资料状态</div>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <span class="inline-flex rounded-full border px-2.5 py-1 text-xs" :class="statusClass(profile.status)">
              {{ statusLabel(profile.status) }}
            </span>
            <span class="inline-flex rounded-full border px-2.5 py-1 text-xs" :class="settlementClass(profile.settlement_status)">
              {{ settlementLabel(profile.settlement_status) }}
            </span>
          </div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="text-xs text-muted-foreground">默认 / 封顶加价</div>
          <div class="mt-3 font-mono text-xl font-semibold">{{ profile.default_markup_percent || '0.00' }}% / {{ profile.max_markup_percent || '0.00' }}%</div>
          <p class="mt-1 text-xs text-muted-foreground">封顶 0 表示不限制。</p>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="text-xs text-muted-foreground">主域名</div>
          <div class="mt-3 truncate font-mono text-sm font-medium">{{ primaryDomain?.domain || '未设置' }}</div>
          <p class="mt-1 text-xs text-muted-foreground">共 {{ domains.length }} 个域名。</p>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="text-xs text-muted-foreground">商品规则</div>
          <div class="mt-3 text-xl font-semibold">{{ detail.product_summary.configured_products }}</div>
          <p class="mt-1 text-xs text-muted-foreground">隐藏 {{ detail.product_summary.hidden_products }}，SKU 覆盖 {{ detail.product_summary.sku_overrides }}。</p>
        </div>
      </div>

      <Tabs v-model="currentTab" class="space-y-4">
        <TabsList class="h-auto flex-wrap gap-1">
          <TabsTrigger value="overview">概览</TabsTrigger>
          <TabsTrigger value="profile">档案与审核</TabsTrigger>
          <TabsTrigger value="domains">域名</TabsTrigger>
          <TabsTrigger value="site">站点配置</TabsTrigger>
          <TabsTrigger value="products">商品规则</TabsTrigger>
          <TabsTrigger value="finance">订单与财务</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" class="mt-0 space-y-4">
          <div class="grid gap-4 lg:grid-cols-3">
            <div class="rounded-xl border border-border bg-card p-4">
              <div class="text-sm font-medium">分销商账号</div>
              <div class="mt-3 space-y-2 text-sm">
                <div class="flex justify-between gap-4"><span class="text-muted-foreground">用户 ID</span><a class="font-mono text-primary hover:underline" :href="userDetailLink" target="_blank">#{{ profile.user_id }}</a></div>
                <div class="flex justify-between gap-4"><span class="text-muted-foreground">邮箱</span><span class="break-all text-right">{{ profile.user?.email || '-' }}</span></div>
                <div class="flex justify-between gap-4"><span class="text-muted-foreground">显示名</span><span>{{ profile.user?.display_name || '-' }}</span></div>
              </div>
            </div>
            <div class="rounded-xl border border-border bg-card p-4">
              <div class="text-sm font-medium">余额摘要</div>
              <div class="mt-3 space-y-2 text-sm">
                <div v-for="balance in detail.finance_summary.balances" :key="balance.id" class="flex justify-between gap-4">
                  <span class="font-mono">{{ balance.currency }}</span>
                  <span class="font-mono">{{ balance.available_amount }} / {{ balance.locked_amount }}</span>
                </div>
                <div v-if="detail.finance_summary.balances.length === 0" class="text-muted-foreground">暂无余额账户。</div>
              </div>
            </div>
            <div class="rounded-xl border border-border bg-card p-4">
              <div class="text-sm font-medium">近期运营</div>
              <div class="mt-3 grid grid-cols-3 gap-3 text-center text-sm">
                <div><div class="text-lg font-semibold">{{ detail.recent_orders.length }}</div><div class="text-xs text-muted-foreground">订单</div></div>
                <div><div class="text-lg font-semibold">{{ detail.recent_ledger_entries.length }}</div><div class="text-xs text-muted-foreground">流水</div></div>
                <div><div class="text-lg font-semibold">{{ detail.recent_withdraws.length }}</div><div class="text-xs text-muted-foreground">提现</div></div>
              </div>
            </div>
          </div>
        </TabsContent>

        <TabsContent value="profile" class="mt-0">
          <div class="rounded-xl border border-border bg-card p-4">
            <div class="grid gap-4 md:grid-cols-2">
              <div>
                <div class="text-xs text-muted-foreground">申请原因</div>
                <p class="mt-2 whitespace-pre-wrap text-sm">{{ profile.apply_reason || '-' }}</p>
              </div>
              <div>
                <div class="text-xs text-muted-foreground">拒绝 / 禁用原因</div>
                <p class="mt-2 whitespace-pre-wrap text-sm">{{ profile.reject_reason || '-' }}</p>
              </div>
              <div>
                <div class="text-xs text-muted-foreground">审核人 / 审核时间</div>
                <p class="mt-2 text-sm"><span class="font-mono">{{ profile.reviewed_by || '-' }}</span> · {{ formatDate(profile.reviewed_at) || '-' }}</p>
              </div>
              <div>
                <div class="text-xs text-muted-foreground">创建 / 更新</div>
                <p class="mt-2 text-sm">{{ formatDate(profile.created_at) }} · {{ formatDate(profile.updated_at) }}</p>
              </div>
            </div>
          </div>
        </TabsContent>

        <TabsContent value="domains" class="mt-0 space-y-4">
          <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_360px]">
            <div class="rounded-xl border border-border bg-card p-4">
              <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                <div>
                  <div class="text-sm font-medium">系统二级域名</div>
                  <p class="mt-1 max-w-2xl text-sm text-muted-foreground">
                    给分销商分配便于品牌传播的二级域名。可填写前缀，例如 hello；也可填写完整域名，例如 hello.shop.example.com。
                  </p>
                </div>
                <span
                  class="inline-flex w-fit rounded-full border px-2.5 py-1 text-xs"
                  :class="systemDomain ? 'border-emerald-200 bg-emerald-50 text-emerald-700' : 'border-amber-200 bg-amber-50 text-amber-700'"
                >
                  {{ systemDomain ? '已分配' : '未分配' }}
                </span>
              </div>
              <form class="mt-4 grid gap-3 md:grid-cols-[minmax(0,1fr)_auto]" @submit.prevent="submitSystemDomain">
                <div class="grid gap-2">
                  <Label for="system-domain">二级域名前缀 / 完整域名</Label>
                  <Input
                    id="system-domain"
                    v-model.trim="systemDomainForm.subdomain"
                    placeholder="hello 或 hello.shop.example.com"
                    :disabled="savingSystemDomain"
                  />
                </div>
                <div class="flex items-end">
                  <Button type="submit" class="w-full md:w-auto" :disabled="savingSystemDomain || !systemDomainForm.subdomain.trim()">
                    {{ savingSystemDomain ? '保存中...' : '保存二级域名' }}
                  </Button>
                </div>
              </form>
              <p class="mt-3 text-xs text-muted-foreground">
                保存后系统域名会自动设为已验证、已启用；如果当前没有主域名，它会自动成为主域名。完整域名必须位于后端配置的 reseller.subdomain_base 下。
              </p>
            </div>

            <div class="rounded-xl border border-border bg-card p-4">
              <div class="text-xs text-muted-foreground">当前系统域名</div>
              <div class="mt-2 break-all font-mono text-sm font-medium text-foreground">{{ systemDomain?.domain || '未分配' }}</div>
              <div class="mt-4 text-xs text-muted-foreground">当前主域名</div>
              <div class="mt-2 break-all font-mono text-sm font-medium text-foreground">{{ primaryDomain?.domain || '未设置' }}</div>
              <p class="mt-3 text-xs text-muted-foreground">共 {{ domains.length }} 个域名，自定义域名仍需在下方审核和设为主域。</p>
            </div>
          </div>

          <div class="overflow-x-auto rounded-xl border border-border bg-card">
            <Table class="min-w-[920px]">
              <TableHeader>
                <TableRow>
                  <TableHead class="px-4 py-3">域名</TableHead>
                  <TableHead class="px-4 py-3">类型</TableHead>
                  <TableHead class="px-4 py-3">验证</TableHead>
                  <TableHead class="px-4 py-3">状态</TableHead>
                  <TableHead class="px-4 py-3">主域</TableHead>
                  <TableHead class="px-4 py-3">验证时间</TableHead>
                  <TableHead class="px-4 py-3 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                <TableRow v-for="domain in domains" :key="domain.id">
                  <TableCell class="px-4 py-3 font-mono text-xs">{{ domain.domain }}</TableCell>
                  <TableCell class="px-4 py-3 text-xs">{{ domainTypeLabel(domain.type) }}</TableCell>
                  <TableCell class="px-4 py-3 text-xs">{{ verificationLabel(domain.verification_status) }}</TableCell>
                  <TableCell class="px-4 py-3 text-xs">{{ domainStatusLabel(domain.status) }}</TableCell>
                  <TableCell class="px-4 py-3 text-xs">{{ domain.is_primary && isActiveVerifiedDomain(domain) ? '是' : '否' }}</TableCell>
                  <TableCell class="px-4 py-3 text-xs text-muted-foreground">{{ formatDate(domain.verified_at) || '-' }}</TableCell>
                  <TableCell class="px-4 py-3 text-right">
                    <Button size="sm" variant="outline" :disabled="operatingDomainId === domain.id || !canSetPrimary(domain)" @click="setPrimaryDomain(domain)">
                      设为主域
                    </Button>
                  </TableCell>
                </TableRow>
                <TableRow v-if="domains.length === 0">
                  <TableCell colspan="7" class="px-4 py-8 text-center text-muted-foreground">暂无域名。</TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
        </TabsContent>

        <TabsContent value="site" class="mt-0">
          <div class="rounded-xl border border-border bg-card p-4">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <div class="text-sm font-medium">{{ detail.site_config?.site_name || '未配置站点名称' }}</div>
                <p class="mt-1 text-sm text-muted-foreground">Logo: {{ detail.site_config?.logo || '-' }}</p>
              </div>
              <Button as="a" variant="outline" :href="siteConfigLink">打开站点配置</Button>
            </div>
            <div class="mt-4 grid gap-3 md:grid-cols-3">
              <div class="rounded-lg border border-border p-3">
                <div class="text-xs text-muted-foreground">公告</div>
                <p class="mt-2 text-sm">{{ getLocalizedText(detail.site_config?.announcement?.title) || '-' }}</p>
              </div>
              <div class="rounded-lg border border-border p-3">
                <div class="text-xs text-muted-foreground">SEO 标题</div>
                <p class="mt-2 text-sm">{{ getLocalizedText(detail.site_config?.seo?.title) || '-' }}</p>
              </div>
              <div class="rounded-lg border border-border p-3">
                <div class="text-xs text-muted-foreground">支持邮箱</div>
                <p class="mt-2 text-sm">{{ detail.site_config?.support?.email || '-' }}</p>
              </div>
            </div>
          </div>
        </TabsContent>

        <TabsContent value="products" class="mt-0">
          <div class="rounded-xl border border-border bg-card p-4">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <div class="text-sm font-medium">商品规则摘要</div>
                <p class="mt-1 text-sm text-muted-foreground">已配置 {{ detail.product_summary.configured_products }} 个商品，隐藏 {{ detail.product_summary.hidden_products }} 个商品，SKU 覆盖 {{ detail.product_summary.sku_overrides }} 条，价格覆盖 {{ detail.product_summary.pricing_overrides }} 条。</p>
              </div>
              <Button as="a" variant="outline" :href="productSettingsLink">打开商品规则</Button>
            </div>
          </div>
        </TabsContent>

        <TabsContent value="finance" class="mt-0 space-y-4">
          <div class="overflow-x-auto rounded-xl border border-border bg-card">
            <div class="flex items-center justify-between border-b border-border px-4 py-3">
              <div class="text-sm font-medium">近期订单</div>
            </div>
            <Table class="min-w-[900px]">
              <TableHeader>
                <TableRow>
                  <TableHead class="px-4 py-3">订单号</TableHead>
                  <TableHead class="px-4 py-3">状态</TableHead>
                  <TableHead class="px-4 py-3">域名</TableHead>
                  <TableHead class="px-4 py-3">金额</TableHead>
                  <TableHead class="px-4 py-3">利润</TableHead>
                  <TableHead class="px-4 py-3">下单时间</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                <TableRow v-for="order in detail.recent_orders" :key="order.order_no">
                  <TableCell class="px-4 py-3 font-mono text-xs">{{ order.order_no }}</TableCell>
                  <TableCell class="px-4 py-3 text-xs">{{ order.status }}</TableCell>
                  <TableCell class="px-4 py-3 font-mono text-xs">{{ order.domain || '-' }}</TableCell>
                  <TableCell class="px-4 py-3 font-mono text-xs">{{ formatMoney(order.total_amount, order.currency) }}</TableCell>
                  <TableCell class="px-4 py-3 font-mono text-xs">{{ formatMoney(order.profit_amount, order.currency) }}</TableCell>
                  <TableCell class="px-4 py-3 text-xs text-muted-foreground">{{ formatDate(order.created_at) }}</TableCell>
                </TableRow>
                <TableRow v-if="detail.recent_orders.length === 0">
                  <TableCell colspan="6" class="px-4 py-8 text-center text-muted-foreground">暂无订单。</TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>

          <div class="grid gap-4 xl:grid-cols-2">
            <div class="overflow-x-auto rounded-xl border border-border bg-card">
              <div class="flex items-center justify-between border-b border-border px-4 py-3">
                <div class="text-sm font-medium">近期流水</div>
                <Button as="a" size="sm" variant="outline" :href="ledgerLink">查看全部</Button>
              </div>
              <Table class="min-w-[620px]">
                <TableHeader>
                  <TableRow>
                    <TableHead class="px-4 py-3">类型</TableHead>
                    <TableHead class="px-4 py-3">金额</TableHead>
                    <TableHead class="px-4 py-3">状态</TableHead>
                    <TableHead class="px-4 py-3">时间</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  <TableRow v-for="entry in detail.recent_ledger_entries" :key="entry.id">
                    <TableCell class="px-4 py-3 text-xs">{{ entry.type }}</TableCell>
                    <TableCell class="px-4 py-3 font-mono text-xs">{{ formatMoney(entry.amount, entry.currency) }}</TableCell>
                    <TableCell class="px-4 py-3 text-xs">{{ entry.status }}</TableCell>
                    <TableCell class="px-4 py-3 text-xs text-muted-foreground">{{ formatDate(entry.created_at) }}</TableCell>
                  </TableRow>
                  <TableRow v-if="detail.recent_ledger_entries.length === 0">
                    <TableCell colspan="4" class="px-4 py-8 text-center text-muted-foreground">暂无流水。</TableCell>
                  </TableRow>
                </TableBody>
              </Table>
            </div>
            <div class="overflow-x-auto rounded-xl border border-border bg-card">
              <div class="flex items-center justify-between border-b border-border px-4 py-3">
                <div class="text-sm font-medium">近期提现</div>
                <Button as="a" size="sm" variant="outline" :href="withdrawLink">查看全部</Button>
              </div>
              <Table class="min-w-[620px]">
                <TableHeader>
                  <TableRow>
                    <TableHead class="px-4 py-3">渠道</TableHead>
                    <TableHead class="px-4 py-3">金额</TableHead>
                    <TableHead class="px-4 py-3">状态</TableHead>
                    <TableHead class="px-4 py-3">时间</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  <TableRow v-for="withdraw in detail.recent_withdraws" :key="withdraw.id">
                    <TableCell class="px-4 py-3 text-xs">{{ withdraw.channel }}</TableCell>
                    <TableCell class="px-4 py-3 font-mono text-xs">{{ formatMoney(withdraw.amount, withdraw.currency) }}</TableCell>
                    <TableCell class="px-4 py-3 text-xs">{{ withdraw.status }}</TableCell>
                    <TableCell class="px-4 py-3 text-xs text-muted-foreground">{{ formatDate(withdraw.created_at) }}</TableCell>
                  </TableRow>
                  <TableRow v-if="detail.recent_withdraws.length === 0">
                    <TableCell colspan="4" class="px-4 py-8 text-center text-muted-foreground">暂无提现。</TableCell>
                  </TableRow>
                </TableBody>
              </Table>
            </div>
          </div>
        </TabsContent>
      </Tabs>
    </template>

    <Dialog v-model:open="showEditDialog">
      <DialogScrollContent class="w-[calc(100vw-1rem)] max-w-lg p-4 sm:p-6">
        <DialogHeader>
          <DialogTitle>编辑分销商运营配置 R#{{ profile?.id || '-' }}</DialogTitle>
        </DialogHeader>
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="grid gap-2">
            <Label>默认加价比例</Label>
            <Input v-model="editForm.defaultMarkup" inputmode="decimal" placeholder="0.00" />
          </div>
          <div class="grid gap-2">
            <Label>封顶加价比例</Label>
            <Input v-model="editForm.maxMarkup" inputmode="decimal" placeholder="0.00" />
          </div>
          <div class="grid gap-2 sm:col-span-2">
            <Label>结算状态</Label>
            <Select v-model="editForm.settlementStatus">
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem :value="RESELLER_SETTLEMENT_STATUS_NORMAL">正常</SelectItem>
                <SelectItem :value="RESELLER_SETTLEMENT_STATUS_FROZEN">结算冻结</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div class="grid gap-2 sm:col-span-2">
            <Label>操作原因</Label>
            <Textarea v-model="editForm.reason" rows="3" />
          </div>
          <p class="text-xs text-muted-foreground sm:col-span-2">封顶加价填写 0 表示不限制；这里不执行手动调账，也不冻结余额账户。</p>
          <div class="flex justify-end gap-2 sm:col-span-2">
            <Button variant="outline" @click="showEditDialog = false">取消</Button>
            <Button :disabled="saving" @click="submitEditProfile">保存配置</Button>
          </div>
        </div>
      </DialogScrollContent>
    </Dialog>
  </div>
</template>
