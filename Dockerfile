# syntax=docker/dockerfile:1.7
# JUKKINGDOM — ไฟล์เดียวจบ: Dockerfile นี้มีโค้ดทั้งระบบ (บอท + เว็บแอป) ฝังอยู่ข้างใน
# วางไฟล์นี้ไฟล์เดียวที่หน้าแรกของ GitHub repo แล้วให้ Railway Deploy ได้เลย
FROM node:22-slim
RUN apt-get update -y && apt-get install -y openssl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY <<"EOF_PKG" /app/package.json
{
  "name": "jukkingdom",
  "version": "0.2.0",
  "private": true,
  "type": "module",
  "engines": { "node": ">=20" },
  "prisma": { "schema": "schema.prisma" },
  "scripts": {
    "postinstall": "prisma generate",
    "dev": "tsx watch index.ts",
    "build": "tsc -p tsconfig.json",
    "start": "prisma db push --skip-generate && node dist/index.js"
  },
  "dependencies": {
    "@prisma/client": "^5.22.0",
    "prisma": "^5.22.0",
    "discord.js": "^14.16.3",
    "express": "^5.1.0",
    "zod": "^3.23.8",
    "pino": "^9.5.0",
    "dotenv": "^16.4.5",
    "typescript": "^5.6.0",
    "tsx": "^4.19.0",
    "@types/node": "^22.0.0",
    "@types/express": "^5.0.0"
  }
}
EOF_PKG

COPY <<"EOF_TSC" /app/tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022", "module": "NodeNext", "moduleResolution": "NodeNext",
    "strict": true, "esModuleInterop": true, "skipLibCheck": true,
    "outDir": "dist", "rootDir": "."
  },
  "include": ["index.ts"]
}
EOF_TSC

COPY <<"EOF_PRISMA" /app/schema.prisma
generator client {
  provider = "prisma-client-js"
}
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

// เงินทั้งหมดเก็บเป็นจำนวนเต็มหน่วยสตางค์ (Int) ห้ามใช้ Float

enum StaffRole { OWNER ADMIN STAFF }
enum OrderStatus { PENDING CONFIRMED IN_PROGRESS WAITING_CUSTOMER REVISION COMPLETED CANCELLED }
enum PaymentStatus { UNPAID PENDING_VERIFICATION PARTIALLY_PAID PAID REJECTED REFUNDED }
enum TicketType { ORDER PRICE_INQUIRY ISSUE CONTACT }
enum TicketStatus { OPEN CLOSED }
enum ModAction { WARN TIMEOUT UNTIMEOUT KICK BAN UNBAN PURGE }

model User {
  id          String   @id @default(cuid())
  discordId   String   @unique
  username    String
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
  orders      Order[]
  tickets     Ticket[]
  reviews     Review[]
  payments    Payment[]
  warnings    Warning[]
  notifications Notification[]
}

model Guild {
  id         String   @id @default(cuid())
  discordId  String   @unique
  name       String?
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
  settings   GuildSettings?
  welcome    WelcomeSettings?
  staff      StaffMember[]
  products   Product[]
  orders     Order[]
  tickets    Ticket[]
  reviews    Review[]
  cases      ModerationCase[]
  rolePanels RolePanel[]
  templates  EmbedTemplate[]
  auditLogs  AuditLog[]
}

model GuildSettings {
  id               String  @id @default(cuid())
  guildId          String  @unique
  guild            Guild   @relation(fields: [guildId], references: [id])
  orderChannelId   String?
  logChannelId     String?
  reviewChannelId  String?
  announceChannelId String?
  ticketCategoryId String?
  adminRoleId      String?
  staffRoleId      String?
  customerRoleId   String?
  embedColor       Int     @default(9109504) // 0x8B0000
  footerText       String?
  imageUrl         String?
  maxOpenTicketsPerUser Int @default(1)
  shopOpen         Boolean @default(true)
  createdAt        DateTime @default(now())
  updatedAt        DateTime @updatedAt
}

model StaffMember {
  id        String    @id @default(cuid())
  guildId   String
  guild     Guild     @relation(fields: [guildId], references: [id])
  discordId String
  role      StaffRole
  createdAt DateTime  @default(now())
  updatedAt DateTime  @updatedAt
  deletedAt DateTime?
  assignedOrders Order[]
  @@unique([guildId, discordId])
}

model Product {
  id        String    @id @default(cuid())
  guildId   String
  guild     Guild     @relation(fields: [guildId], references: [id])
  name      String
  description String?
  sortOrder Int       @default(0)
  active    Boolean   @default(true)
  createdAt DateTime  @default(now())
  updatedAt DateTime  @updatedAt
  deletedAt DateTime?
  packages  ProductPackage[]
  @@index([guildId, active])
}

model ProductPackage {
  id            String    @id @default(cuid())
  productId     String
  product       Product   @relation(fields: [productId], references: [id])
  name          String
  description   String?
  priceSatang   Int
  etaDays       Int?
  coverUrl      String?
  inclusions    String[]
  isCustom      Boolean   @default(false)
  sortOrder     Int       @default(0)
  active        Boolean   @default(true)
  createdAt     DateTime  @default(now())
  updatedAt     DateTime  @updatedAt
  deletedAt     DateTime?
  orderItems    OrderItem[]
  @@index([productId, active, sortOrder])
}

model Order {
  id             String        @id @default(cuid())
  orderNo        String        @unique
  idempotencyKey String        @unique // เช่น interaction.id กันออเดอร์ซ้ำ
  guildId        String
  guild          Guild         @relation(fields: [guildId], references: [id])
  customerId     String
  customer       User          @relation(fields: [customerId], references: [id])
  assigneeId     String?
  assignee       StaffMember?  @relation(fields: [assigneeId], references: [id])
  status         OrderStatus   @default(PENDING)
  paymentStatus  PaymentStatus @default(UNPAID)
  priceSatang    Int           @default(0)
  paidSatang     Int           @default(0)
  budgetSatang   Int?
  details        String
  referenceLinks String[]
  dueDate        DateTime?
  internalNote   String?
  cancelReason   String?
  version        Int           @default(0) // optimistic lock
  createdAt      DateTime      @default(now())
  updatedAt      DateTime      @updatedAt
  deletedAt      DateTime?
  items          OrderItem[]
  history        OrderStatusHistory[]
  tickets        Ticket[]
  payments       Payment[]
  review         Review?
  @@index([guildId, status])
  @@index([customerId])
}

model OrderItem {
  id          String         @id @default(cuid())
  orderId     String
  order       Order          @relation(fields: [orderId], references: [id])
  packageId   String
  package     ProductPackage @relation(fields: [packageId], references: [id])
  nameSnapshot String
  priceSatang Int
  quantity    Int            @default(1)
}

model OrderStatusHistory {
  id         String      @id @default(cuid())
  orderId    String
  order      Order       @relation(fields: [orderId], references: [id])
  fromStatus OrderStatus?
  toStatus   OrderStatus
  actorDiscordId String
  note       String?
  createdAt  DateTime    @default(now())
  @@index([orderId])
}

model Ticket {
  id         String       @id @default(cuid())
  ticketNo   Int          @default(autoincrement())
  guildId    String
  guild      Guild        @relation(fields: [guildId], references: [id])
  channelId  String?      @unique
  customerId String
  customer   User         @relation(fields: [customerId], references: [id])
  orderId    String?
  order      Order?       @relation(fields: [orderId], references: [id])
  type       TicketType
  status     TicketStatus @default(OPEN)
  claimedByDiscordId String?
  openedAt   DateTime     @default(now())
  closedAt   DateTime?
  closedByDiscordId String?
  createdAt  DateTime     @default(now())
  updatedAt  DateTime     @updatedAt
  participants TicketParticipant[]
  messages   TicketMessage[]
  @@index([guildId, status])
  @@index([customerId, status])
}

model TicketParticipant {
  id        String   @id @default(cuid())
  ticketId  String
  ticket    Ticket   @relation(fields: [ticketId], references: [id])
  discordId String
  addedByDiscordId String?
  createdAt DateTime @default(now())
  @@unique([ticketId, discordId])
}

// Transcript: เก็บเมื่อปิด Ticket เข้าถึงได้เฉพาะผู้มีสิทธิ์
model TicketMessage {
  id        String   @id @default(cuid())
  ticketId  String
  ticket    Ticket   @relation(fields: [ticketId], references: [id])
  authorDiscordId String
  authorName String
  content   String
  sentAt    DateTime
  @@index([ticketId, sentAt])
}

model Payment {
  id          String        @id @default(cuid())
  orderId     String
  order       Order         @relation(fields: [orderId], references: [id])
  customerId  String
  customer    User          @relation(fields: [customerId], references: [id])
  amountSatang Int
  status      PaymentStatus @default(PENDING_VERIFICATION)
  proofUrl    String?
  createdAt   DateTime      @default(now())
  updatedAt   DateTime      @updatedAt
  verifications PaymentVerification[]
  @@index([orderId])
}

model PaymentVerification {
  id          String        @id @default(cuid())
  paymentId   String
  payment     Payment       @relation(fields: [paymentId], references: [id])
  verifierDiscordId String
  fromStatus  PaymentStatus
  toStatus    PaymentStatus
  note        String?
  createdAt   DateTime      @default(now())
}

model Review {
  id         String   @id @default(cuid())
  guildId    String
  guild      Guild    @relation(fields: [guildId], references: [id])
  orderId    String   @unique // 1 ออเดอร์ รีวิวได้ครั้งเดียว
  order      Order    @relation(fields: [orderId], references: [id])
  customerId String
  customer   User     @relation(fields: [customerId], references: [id])
  rating     Int      // 1-5 (ตรวจใน Service)
  comment    String?
  hidden     Boolean  @default(false)
  hiddenReason String?
  hiddenByDiscordId String?
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
  @@index([guildId, hidden])
}

model ModerationCase {
  id        String    @id @default(cuid())
  caseNo    Int       @default(autoincrement())
  guildId   String
  guild     Guild     @relation(fields: [guildId], references: [id])
  action    ModAction
  targetDiscordId String
  moderatorDiscordId String
  reason    String
  expiresAt DateTime?
  createdAt DateTime  @default(now())
  @@index([guildId, targetDiscordId])
}

model Warning {
  id        String   @id @default(cuid())
  userId    String
  user      User     @relation(fields: [userId], references: [id])
  guildDiscordId String
  moderatorDiscordId String
  reason    String
  createdAt DateTime @default(now())
  deletedAt DateTime?
  @@index([guildDiscordId, userId])
}

model WelcomeSettings {
  id        String   @id @default(cuid())
  guildId   String   @unique
  guild     Guild    @relation(fields: [guildId], references: [id])
  enabled   Boolean  @default(false)
  channelId String?
  message   String   @default("ยินดีต้อนรับ {user} สู่ {server} คุณคือสมาชิกคนที่ {memberCount}")
  embedColor Int?
  thumbnailUrl String?
  imageUrl  String?
  updatedAt DateTime @updatedAt
}

model RolePanel {
  id        String   @id @default(cuid())
  guildId   String
  guild     Guild    @relation(fields: [guildId], references: [id])
  channelId String?
  messageId String?
  title     String
  mode      String   @default("BUTTON") // BUTTON | SELECT
  roleIds   String[]
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
}

model EmbedTemplate {
  id        String   @id @default(cuid())
  guildId   String
  guild     Guild    @relation(fields: [guildId], references: [id])
  name      String
  data      Json
  createdByDiscordId String
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  deletedAt DateTime?
  @@unique([guildId, name])
}

model Notification {
  id        String   @id @default(cuid())
  userId    String
  user      User     @relation(fields: [userId], references: [id])
  title     String
  body      String
  readAt    DateTime?
  createdAt DateTime @default(now())
  @@index([userId, readAt])
}

model AuditLog {
  id        String   @id @default(cuid())
  guildId   String
  guild     Guild    @relation(fields: [guildId], references: [id])
  actorDiscordId String
  action    String
  entity    String
  entityId  String?
  before    Json?
  after     Json?
  createdAt DateTime @default(now())
  @@index([guildId, createdAt])
}
EOF_PRISMA

COPY <<"EOF_INDEX" /app/index.ts
// JUKKINGDOM — บอท Discord + เว็บแอปจัดการร้าน (ไฟล์เดียว)
import "dotenv/config";
import { OrderStatus, Prisma, PrismaClient } from "@prisma/client";
import { ActionRowBuilder, ChannelType, ChatInputCommandInteraction, Client, EmbedBuilder, Events, GatewayIntentBits, GuildMember, Interaction, ModalBuilder, ModalSubmitInteraction, PermissionFlagsBits, REST, Routes, SlashCommandBuilder, SlashCommandOptionsOnlyBuilder, StringSelectMenuBuilder, StringSelectMenuInteraction, TextBasedChannel, TextInputBuilder, TextInputStyle } from "discord.js";
import express, { NextFunction, Request, Response, Router } from "express";
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import pino from "pino";
import { z } from "zod";

// ===== config.ts =====
const envSchema = z.object({
  DISCORD_TOKEN: z.string().min(20),
  DISCORD_CLIENT_ID: z.string().min(5),
  DISCORD_CLIENT_SECRET: z.string().min(10),
  DISCORD_GUILD_ID: z.string().regex(/^\d{15,25}$/),
  OWNER_DISCORD_ID: z.string().regex(/^\d{15,25}$/),
  DATABASE_URL: z.string().min(10),
  SESSION_SECRET: z.string().min(32),
  BASE_URL: z.string().url().transform((v) => v.replace(/\/+$/, "")),
  PORT: z.coerce.number().default(3000),
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  LOG_LEVEL: z.string().default("info"),
});

const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
  // แสดงเฉพาะชื่อตัวแปรที่ผิด ไม่แสดงค่า
  console.error("ตั้งค่า Environment ไม่ถูกต้อง ตรวจตัวแปรเหล่านี้:", Object.keys(parsed.error.flatten().fieldErrors).join(", "));
  process.exit(1);
}
const config = parsed.data;
const BRAND_COLOR = 0x8b0000;

// ===== logger.ts =====
const logger = pino({
  level: config.LOG_LEVEL,
  redact: ["token", "*.token", "password", "*.password", "DISCORD_TOKEN", "DISCORD_CLIENT_SECRET", "SESSION_SECRET", "DATABASE_URL"],
});

// ===== db.ts =====
const prisma = new PrismaClient();

// ===== lib/money.ts =====
/** บาท (ทศนิยม ≤2 ตำแหน่ง) -> สตางค์ (Int) ไม่ใช้ Float คำนวณเงิน */
function bahtToSatang(input: string): number | null {
  const m = /^(\d{1,7})(?:\.(\d{1,2}))?$/.exec(input.trim().replace(/,/g, ""));
  if (!m) return null;
  return parseInt(m[1], 10) * 100 + parseInt((m[2] ?? "").padEnd(2, "0") || "0", 10);
}
function formatBaht(satang: number): string {
  const baht = Math.trunc(satang / 100);
  const s = satang % 100;
  return `฿${baht.toLocaleString("en-US")}${s ? "." + String(s).padStart(2, "0") : ""}`;
}
function satangToInput(satang: number): string {
  return (satang / 100).toFixed(2).replace(/\.00$/, "");
}

// ===== lib/format.ts =====
const ORDER_STATUS_TH: Record<string, string> = {
  PENDING: "รอตรวจสอบ", CONFIRMED: "ยืนยันออเดอร์แล้ว", IN_PROGRESS: "กำลังดำเนินงาน",
  WAITING_CUSTOMER: "รอข้อมูลจากลูกค้า", REVISION: "กำลังแก้ไขงาน", COMPLETED: "เสร็จสิ้น", CANCELLED: "ยกเลิก",
};
const PAYMENT_STATUS_TH: Record<string, string> = {
  UNPAID: "ยังไม่ชำระ", PENDING_VERIFICATION: "รอตรวจสอบหลักฐาน", PARTIALLY_PAID: "ชำระบางส่วน",
  PAID: "ชำระแล้ว", REJECTED: "ปฏิเสธหลักฐาน", REFUNDED: "คืนเงินแล้ว",
};
/** สถานะที่เปลี่ยนต่อได้ */
const TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  PENDING: ["CONFIRMED", "CANCELLED"],
  CONFIRMED: ["IN_PROGRESS", "WAITING_CUSTOMER", "CANCELLED"],
  IN_PROGRESS: ["WAITING_CUSTOMER", "REVISION", "COMPLETED", "CANCELLED"],
  WAITING_CUSTOMER: ["IN_PROGRESS", "CANCELLED"],
  REVISION: ["IN_PROGRESS", "COMPLETED", "CANCELLED"],
  COMPLETED: ["REVISION"],
  CANCELLED: [],
};
const thDate = (d: Date | null | undefined) =>
  d ? d.toLocaleString("th-TH", { timeZone: "Asia/Bangkok", dateStyle: "medium", timeStyle: "short" }) : "-";
const thDay = (d: Date | null | undefined) =>
  d ? d.toLocaleDateString("th-TH", { timeZone: "Asia/Bangkok", dateStyle: "medium" }) : "-";

// ===== lib/embeds.ts =====
const brandEmbed = (color: number = BRAND_COLOR) => new EmbedBuilder().setColor(color).setFooter({ text: "JUKKINGDOM" }).setTimestamp();
const errorEmbed = (msg: string) => brandEmbed(0xe11d48).setTitle("เกิดข้อผิดพลาด").setDescription(msg);

// ===== services/guild.ts =====
async function getGuild() {
  return prisma.guild.upsert({
    where: { discordId: config.DISCORD_GUILD_ID }, update: {}, create: { discordId: config.DISCORD_GUILD_ID },
  });
}
async function getSettings() {
  const guild = await getGuild();
  const settings = await prisma.guildSettings.upsert({ where: { guildId: guild.id }, update: {}, create: { guildId: guild.id } });
  return { guild, settings };
}

// ===== services/audit.ts =====
type Db = Pick<PrismaClient, "auditLog">;
async function audit(
  db: Db, guildId: string, actorDiscordId: string, action: string, entity: string,
  entityId?: string, before?: unknown, after?: unknown,
) {
  await db.auditLog.create({
    data: {
      guildId, actorDiscordId, action, entity, entityId,
      before: (before ?? undefined) as Prisma.InputJsonValue | undefined,
      after: (after ?? undefined) as Prisma.InputJsonValue | undefined,
    },
  });
}

// ===== permissions.ts =====
type Level = "CUSTOMER" | "STAFF" | "ADMIN" | "OWNER";
const rank: Record<Level, number> = { CUSTOMER: 0, STAFF: 1, ADMIN: 2, OWNER: 3 };
const atLeast = (l: Level, min: Level) => rank[l] >= rank[min];

/** หา StaffMember จาก Discord ID (ตรวจจากฐานข้อมูลทุกครั้ง) เจ้าของร้านใน env จะถูกสร้างเป็น OWNER อัตโนมัติ */
async function resolveStaff(discordId: string) {
  const guild = await getGuild();
  if (discordId === config.OWNER_DISCORD_ID) {
    return prisma.staffMember.upsert({
      where: { guildId_discordId: { guildId: guild.id, discordId } },
      update: { role: "OWNER", deletedAt: null },
      create: { guildId: guild.id, discordId, role: "OWNER" },
    });
  }
  return prisma.staffMember.findFirst({ where: { guildId: guild.id, discordId, deletedAt: null } });
}

/** ระดับสิทธิ์ของสมาชิกใน Discord (ฝั่งบอท) */
async function getBotLevel(member: GuildMember): Promise<Level> {
  if (member.id === config.OWNER_DISCORD_ID || member.guild.ownerId === member.id) return "OWNER";
  const s = await resolveStaff(member.id);
  if (s) return s.role;
  if (member.permissions.has(PermissionFlagsBits.Administrator)) return "ADMIN";
  return "CUSTOMER";
}

// ===== notify.ts =====
let client: Client | null = null;
const setClient = (c: Client) => { client = c; };

/** ส่ง DM ให้ลูกค้า (DM ปิดอยู่ก็ไม่ทำให้ระบบล้ม) */
async function dmUser(discordId: string, embed: EmbedBuilder) {
  try {
    if (!client) return false;
    const u = await client.users.fetch(discordId);
    await u.send({ embeds: [embed] });
    return true;
  } catch (err) {
    logger.warn({ err: String(err) }, "dm failed");
    return false;
  }
}

async function postToChannel(key: "orderChannelId" | "logChannelId" | "reviewChannelId", embed: EmbedBuilder) {
  try {
    if (!client) return;
    const { settings } = await getSettings();
    const id = settings[key];
    if (!id) return;
    const ch = (await client.channels.fetch(id)) as TextBasedChannel | null;
    if (ch && "send" in ch) await ch.send({ embeds: [embed] });
  } catch (err) {
    logger.warn({ err: String(err), key }, "post to channel failed");
  }
}

// ===== services/orders.ts =====
class AppError extends Error {
  constructor(public code: string, message: string) { super(message); }
}

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const newOrderNo = () => "JK-" + Array.from(randomBytes(6), (x) => ALPHABET[x % ALPHABET.length]).join("");

interface CreateOrderInput {
  customerDiscordId: string; customerName: string; packageId: string; details: string;
  referenceLinks: string[]; budgetSatang: number | null; dueDate: Date | null; idempotencyKey: string;
}

/** สร้างออเดอร์ใน Transaction เดียว กดซ้ำ (idempotencyKey เดิม) = ได้ออเดอร์เดิม */
async function createOrder(input: CreateOrderInput) {
  const guild = await getGuild();
  const existing = await prisma.order.findUnique({ where: { idempotencyKey: input.idempotencyKey } });
  if (existing) return { order: existing, created: false as const };

  const pkg = await prisma.productPackage.findFirst({
    where: { id: input.packageId, active: true, deletedAt: null, product: { guildId: guild.id, active: true, deletedAt: null } },
  });
  if (!pkg) throw new AppError("PACKAGE_UNAVAILABLE", "แพ็กเกจนี้ไม่เปิดขายแล้ว");

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const order = await prisma.$transaction(async (tx) => {
        const user = await tx.user.upsert({
          where: { discordId: input.customerDiscordId },
          update: { username: input.customerName },
          create: { discordId: input.customerDiscordId, username: input.customerName },
        });
        return tx.order.create({
          data: {
            orderNo: newOrderNo(), idempotencyKey: input.idempotencyKey, guildId: guild.id, customerId: user.id,
            priceSatang: pkg.isCustom ? 0 : pkg.priceSatang, // ราคามาจากฐานข้อมูลเท่านั้น
            budgetSatang: input.budgetSatang, details: input.details,
            referenceLinks: input.referenceLinks, dueDate: input.dueDate,
            items: { create: { packageId: pkg.id, nameSnapshot: pkg.name, priceSatang: pkg.priceSatang } },
            history: { create: { toStatus: "PENDING", actorDiscordId: input.customerDiscordId, note: "ลูกค้าสร้างออเดอร์" } },
          },
        });
      });
      await postToChannel("orderChannelId", brandEmbed().setTitle("ออเดอร์ใหม่ " + order.orderNo)
        .setDescription(`ลูกค้า <@${input.customerDiscordId}> สั่ง **${pkg.name}**\n${config.BASE_URL}/orders/${order.id}`));
      return { order, created: true as const };
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
        const dup = await prisma.order.findUnique({ where: { idempotencyKey: input.idempotencyKey } });
        if (dup) return { order: dup, created: false as const };
        continue; // เลขออเดอร์ชน -> สุ่มใหม่
      }
      throw e;
    }
  }
  throw new AppError("ORDER_NO_COLLISION", "สร้างเลขออเดอร์ไม่สำเร็จ");
}

/** เปลี่ยนสถานะ: ตรวจลำดับที่อนุญาต + ล็อกกันแก้พร้อมกัน + บันทึกประวัติ/Audit + แจ้งลูกค้า */
async function changeStatus(a: { orderId: string; to: OrderStatus; actorDiscordId: string; note?: string }) {
  const guild = await getGuild();
  const cur = await prisma.$transaction(async (tx) => {
    const o = await tx.order.findFirst({ where: { id: a.orderId, guildId: guild.id, deletedAt: null }, include: { customer: true } });
    if (!o) throw new AppError("NOT_FOUND", "ไม่พบออเดอร์");
    if (!TRANSITIONS[o.status].includes(a.to))
      throw new AppError("BAD_TRANSITION", `เปลี่ยนจาก "${ORDER_STATUS_TH[o.status]}" เป็น "${ORDER_STATUS_TH[a.to]}" ไม่ได้`);
    if (a.to === "CANCELLED" && !a.note?.trim()) throw new AppError("REASON_REQUIRED", "ต้องระบุเหตุผลที่ยกเลิก");
    const upd = await tx.order.updateMany({
      where: { id: o.id, version: o.version },
      data: { status: a.to, version: { increment: 1 }, ...(a.to === "CANCELLED" ? { cancelReason: a.note } : {}) },
    });
    if (upd.count !== 1) throw new AppError("CONFLICT", "มีคนแก้ออเดอร์นี้พร้อมกัน กรุณารีเฟรชแล้วลองใหม่");
    await tx.orderStatusHistory.create({
      data: { orderId: o.id, fromStatus: o.status, toStatus: a.to, actorDiscordId: a.actorDiscordId, note: a.note || null },
    });
    await audit(tx, guild.id, a.actorDiscordId, "order.status", "Order", o.id, { status: o.status }, { status: a.to, note: a.note });
    return o;
  });
  const e = brandEmbed().setTitle(`อัปเดตออเดอร์ ${cur.orderNo}`)
    .setDescription(`สถานะใหม่: **${ORDER_STATUS_TH[a.to]}**${a.note ? `\nหมายเหตุ: ${a.note}` : ""}`);
  await dmUser(cur.customer.discordId, e);
  await postToChannel("logChannelId", brandEmbed().setTitle("เปลี่ยนสถานะ " + cur.orderNo)
    .setDescription(`${ORDER_STATUS_TH[cur.status]} → ${ORDER_STATUS_TH[a.to]} โดย <@${a.actorDiscordId}>`));
}

interface OrderPatch { internalNote?: string | null; priceSatang?: number; dueDate?: Date | null; assigneeId?: string | null }

async function updateOrder(orderId: string, actorDiscordId: string, patch: OrderPatch) {
  const guild = await getGuild();
  await prisma.$transaction(async (tx) => {
    const o = await tx.order.findFirst({ where: { id: orderId, guildId: guild.id, deletedAt: null } });
    if (!o) throw new AppError("NOT_FOUND", "ไม่พบออเดอร์");
    if (patch.priceSatang !== undefined && patch.priceSatang < o.paidSatang)
      throw new AppError("PRICE_LOW", "ราคาต้องไม่น้อยกว่ายอดที่ชำระแล้ว");
    if (patch.assigneeId) {
      const s = await tx.staffMember.findFirst({ where: { id: patch.assigneeId, guildId: guild.id, deletedAt: null } });
      if (!s) throw new AppError("BAD_ASSIGNEE", "ไม่พบทีมงานคนนี้");
    }
    const upd = await tx.order.updateMany({ where: { id: o.id, version: o.version }, data: { ...patch, version: { increment: 1 } } });
    if (upd.count !== 1) throw new AppError("CONFLICT", "มีคนแก้ออเดอร์นี้พร้อมกัน กรุณารีเฟรชแล้วลองใหม่");
    const before: Record<string, unknown> = {}; const after: Record<string, unknown> = {};
    for (const k of Object.keys(patch) as (keyof OrderPatch)[]) { before[k] = o[k]; after[k] = patch[k]; }
    await audit(tx, guild.id, actorDiscordId, "order.update", "Order", o.id, before, after);
  });
}

/** บันทึกยอดที่ได้รับจริง (ทีมงานยืนยันเอง ระบบไม่เชื่อมธนาคาร/Payment Gateway) */
async function recordPayment(orderId: string, amountSatang: number, actorDiscordId: string, note?: string) {
  const guild = await getGuild();
  if (!Number.isInteger(amountSatang) || amountSatang <= 0) throw new AppError("BAD_AMOUNT", "ยอดเงินไม่ถูกต้อง");
  const o = await prisma.$transaction(async (tx) => {
    const cur = await tx.order.findFirst({ where: { id: orderId, guildId: guild.id, deletedAt: null }, include: { customer: true } });
    if (!cur) throw new AppError("NOT_FOUND", "ไม่พบออเดอร์");
    if (cur.status === "CANCELLED") throw new AppError("CANCELLED", "ออเดอร์ที่ยกเลิกแล้วรับชำระไม่ได้");
    if (cur.priceSatang <= 0) throw new AppError("NO_PRICE", "ตั้งราคาออเดอร์ก่อนบันทึกยอดชำระ");
    const newPaid = cur.paidSatang + amountSatang;
    if (newPaid > cur.priceSatang) throw new AppError("OVERPAY", "ยอดรวมที่ชำระเกินราคาออเดอร์");
    const to = newPaid === cur.priceSatang ? "PAID" : "PARTIALLY_PAID";
    const upd = await tx.order.updateMany({
      where: { id: cur.id, version: cur.version },
      data: { paidSatang: newPaid, paymentStatus: to, version: { increment: 1 } },
    });
    if (upd.count !== 1) throw new AppError("CONFLICT", "มีคนแก้ออเดอร์นี้พร้อมกัน กรุณารีเฟรชแล้วลองใหม่");
    const p = await tx.payment.create({ data: { orderId: cur.id, customerId: cur.customerId, amountSatang, status: to } });
    await tx.paymentVerification.create({
      data: { paymentId: p.id, verifierDiscordId: actorDiscordId, fromStatus: cur.paymentStatus, toStatus: to, note: note || null },
    });
    await audit(tx, guild.id, actorDiscordId, "order.payment", "Order", cur.id, { paid: cur.paidSatang }, { paid: newPaid, amount: amountSatang });
    return { cur, newPaid, to };
  });
  await dmUser(o.cur.customer.discordId, brandEmbed().setTitle(`บันทึกการชำระเงิน ${o.cur.orderNo}`)
    .setDescription(`ได้รับ ${formatBaht(amountSatang)} (รวม ${formatBaht(o.newPaid)} / ${formatBaht(o.cur.priceSatang)})`));
}

/** ลูกค้าเห็นเฉพาะออเดอร์ของตัวเอง */
const listOrdersForCustomer = (customerDiscordId: string) =>
  prisma.order.findMany({ where: { deletedAt: null, customer: { discordId: customerDiscordId } }, orderBy: { createdAt: "desc" }, take: 10 });

// ===== services/reviews.ts =====
async function createReview(a: { orderNo: string; customerDiscordId: string; rating: number; comment?: string }) {
  if (!Number.isInteger(a.rating) || a.rating < 1 || a.rating > 5) throw new AppError("BAD_RATING", "คะแนนต้อง 1-5");
  const guild = await getGuild();
  const o = await prisma.order.findFirst({
    where: { orderNo: a.orderNo.trim().toUpperCase(), guildId: guild.id, deletedAt: null, customer: { discordId: a.customerDiscordId } },
  });
  if (!o) throw new AppError("NOT_FOUND", "ไม่พบออเดอร์นี้ในบัญชีของคุณ");
  if (o.status !== "COMPLETED") throw new AppError("NOT_COMPLETED", "รีวิวได้เมื่อออเดอร์เสร็จสิ้นแล้วเท่านั้น");
  try {
    await prisma.review.create({
      data: { guildId: guild.id, orderId: o.id, customerId: o.customerId, rating: a.rating, comment: a.comment?.trim() || null },
    });
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") throw new AppError("DUP", "ออเดอร์นี้รีวิวไปแล้ว");
    throw e;
  }
  await postToChannel("reviewChannelId", brandEmbed().setTitle(`รีวิวใหม่ ${"★".repeat(a.rating)}${"☆".repeat(5 - a.rating)}`)
    .setDescription(a.comment?.trim() || "(ไม่มีข้อความ)").addFields({ name: "ออเดอร์", value: o.orderNo }));
}

async function ratingSummary() {
  const guild = await getGuild();
  const r = await prisma.review.aggregate({ where: { guildId: guild.id, hidden: false }, _avg: { rating: true }, _count: true });
  return { avg: r._avg.rating, count: r._count };
}

// ===== web/html.ts =====
const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

interface ViewUser { name: string; level: Level; csrf: string }
const NAV: [string, string, Level][] = [
  ["/", "ภาพรวม", "STAFF"], ["/orders", "ออเดอร์", "STAFF"], ["/packages", "แพ็กเกจ", "ADMIN"],
  ["/customers", "ลูกค้า", "ADMIN"], ["/reviews", "รีวิว", "ADMIN"], ["/settings", "ตั้งค่า", "ADMIN"],
  ["/staff", "ทีมงาน", "OWNER"], ["/audit", "Audit Log", "ADMIN"],
];
const LEVEL_TH: Record<string, string> = { OWNER: "เจ้าของ", ADMIN: "แอดมิน", STAFF: "ทีมงาน" };

const CSS = `
:root{--bg:#0b0b0c;--card:#161618;--line:#2a2a2e;--red:#8b0000;--red2:#e11d48;--text:#f4f4f5;--muted:#9ca3af;--ok:#16a34a;--warn:#d97706}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,-apple-system,"Noto Sans Thai",sans-serif}
a{color:#fca5a5}a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible,textarea:focus-visible,summary:focus-visible{outline:2px solid var(--red2);outline-offset:2px}
header{background:#111113;border-bottom:1px solid var(--line);padding:10px 16px;display:flex;gap:12px;align-items:center;flex-wrap:wrap;position:sticky;top:0;z-index:5}
.brand{font-weight:800;letter-spacing:.08em;color:#fff}.brand b{color:var(--red2)}
nav{display:flex;gap:4px;flex-wrap:wrap;flex:1}nav a{padding:6px 10px;border-radius:8px;text-decoration:none;color:var(--muted)}
nav a:hover{background:#1f1f22;color:#fff}nav a.on{background:var(--red);color:#fff}
.me{display:flex;gap:8px;align-items:center;color:var(--muted);font-size:13px}
main{max-width:1100px;margin:0 auto;padding:16px}h1{font-size:22px;margin:4px 0 14px}h2{font-size:17px;margin:0 0 10px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:14px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}
.stat{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px}.stat b{display:block;font-size:24px}.stat span{color:var(--muted);font-size:13px}
.wrap{overflow-x:auto}table{width:100%;border-collapse:collapse;min-width:640px}th,td{text-align:left;padding:8px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-weight:600;font-size:13px}
input,select,textarea{background:#0f0f11;color:var(--text);border:1px solid var(--line);border-radius:8px;padding:8px 10px;font:inherit;max-width:100%}
textarea{width:100%;min-height:70px}label{display:block;color:var(--muted);font-size:13px;margin:8px 0 3px}
button,.btn{background:var(--red);color:#fff;border:0;border-radius:8px;padding:8px 14px;font:inherit;cursor:pointer;text-decoration:none;display:inline-block}
button:hover{background:#a50000}.danger{background:var(--red2)}.ghost{background:#26262a}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:end}
.badge{display:inline-block;padding:2px 8px;border-radius:99px;font-size:12px;border:1px solid var(--line);background:#1f1f22}
.b-ok{border-color:var(--ok);color:#86efac}.b-warn{border-color:var(--warn);color:#fcd34d}.b-bad{border-color:var(--red2);color:#fca5a5}
.msg{padding:10px 12px;border-radius:8px;margin-bottom:12px;border:1px solid}.msg.ok{border-color:var(--ok);color:#86efac}.msg.err{border-color:var(--red2);color:#fca5a5}
.muted{color:var(--muted)}.bars{display:flex;align-items:flex-end;gap:4px;height:90px}.bars div{flex:1;background:var(--red);border-radius:4px 4px 0 0;min-height:2px}
.pager{display:flex;gap:8px;margin-top:10px}details summary{cursor:pointer;color:#fca5a5}
@media(max-width:640px){main{padding:10px}}`;

function layout(o: { title: string; user?: ViewUser; active?: string; body: string; msg?: { text: string; ok: boolean } }) {
  const nav = o.user ? NAV.filter(([, , min]) => atLeast(o.user!.level, min))
    .map(([h, l]) => `<a href="${h}" class="${o.active === h ? "on" : ""}">${l}</a>`).join("") : "";
  const me = o.user ? `<div class="me"><span>${esc(o.user.name)} · ${LEVEL_TH[o.user.level] ?? ""}</span>
    <form method="post" action="/logout">${csrf(o.user)}<button class="ghost" type="submit">ออกจากระบบ</button></form></div>` : "";
  return `<!doctype html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(o.title)} · JUKKINGDOM</title><style>${CSS}</style></head><body>
<header><div class="brand">JUK<b>KINGDOM</b></div><nav aria-label="เมนูหลัก">${nav}</nav>${me}</header>
<main>${o.msg ? `<div class="msg ${o.msg.ok ? "ok" : "err"}" role="status">${esc(o.msg.text)}</div>` : ""}${o.body}</main></body></html>`;
}

const csrf = (u: { csrf: string }) => `<input type="hidden" name="_csrf" value="${esc(u.csrf)}">`;

const badge = (text: string, kind: "ok" | "warn" | "bad" | "" = "") => `<span class="badge ${kind ? "b-" + kind : ""}">${esc(text)}</span>`;
const orderBadge = (s: string, label: string) =>
  badge(label, s === "COMPLETED" ? "ok" : s === "CANCELLED" ? "bad" : s === "PENDING" || s === "WAITING_CUSTOMER" ? "warn" : "");
const payBadge = (s: string, label: string) => badge(label, s === "PAID" ? "ok" : s === "REJECTED" ? "bad" : s === "UNPAID" ? "warn" : "");

function pager(base: string, page: number, hasNext: boolean) {
  const link = (p: number) => `${base}${base.includes("?") ? "&" : "?"}page=${p}`;
  return `<div class="pager">${page > 1 ? `<a class="btn ghost" href="${esc(link(page - 1))}">ก่อนหน้า</a>` : ""}<span class="muted">หน้า ${page}</span>${hasNext ? `<a class="btn ghost" href="${esc(link(page + 1))}">ถัดไป</a>` : ""}</div>`;
}
const loginPage = (err?: string) => layout({
  title: "เข้าสู่ระบบ",
  body: `<div class="card" style="max-width:420px;margin:60px auto;text-align:center"><h1>JUKKINGDOM Dashboard</h1>
  <p class="muted">สำหรับเจ้าของร้านและทีมงานเท่านั้น</p>${err ? `<p class="msg err">${esc(err)}</p>` : ""}
  <a class="btn" href="/login/start">เข้าสู่ระบบด้วย Discord</a></div>`,
});

// ===== web/session.ts =====
interface SessionUser { uid: string; name: string; csrf: string; exp: number }
interface ReqUser extends SessionUser { level: Level; staffId: string }
declare global { namespace Express { interface Request { user?: ReqUser } } }

const COOKIE = "jk_session";
const sign = (v: string) => createHmac("sha256", config.SESSION_SECRET).update(v).digest("base64url");
const safeEq = (a: string, b: string) => { const x = Buffer.from(a), y = Buffer.from(b); return x.length === y.length && timingSafeEqual(x, y); };

function parseCookies(req: Request): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of (req.headers.cookie ?? "").split(";")) {
    const i = part.indexOf("="); if (i < 0) continue;
    out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}
const cookieOpts = { httpOnly: true, sameSite: "lax" as const, secure: config.NODE_ENV === "production", path: "/" };

function startSession(res: Response, uid: string, name: string) {
  const payload: SessionUser = { uid, name, csrf: randomBytes(24).toString("base64url"), exp: Date.now() + 12 * 3600 * 1000 };
  const b = Buffer.from(JSON.stringify(payload)).toString("base64url");
  res.cookie(COOKIE, `${b}.${sign(b)}`, { ...cookieOpts, maxAge: 12 * 3600 * 1000 });
}
const endSession = (res: Response) => res.clearCookie(COOKIE, cookieOpts);
function setStateCookie(res: Response, state: string) { res.cookie("jk_state", state, { ...cookieOpts, maxAge: 10 * 60 * 1000 }); }

/** อ่าน Session แล้วตรวจสิทธิ์จากฐานข้อมูลทุกครั้ง (ถูกถอดสิทธิ์ = เข้าไม่ได้ทันที) */
async function loadUser(req: Request, res: Response, next: NextFunction) {
  const raw = parseCookies(req)[COOKIE];
  if (raw) {
    const [b, sig] = raw.split(".");
    if (b && sig && safeEq(sig, sign(b))) {
      try {
        const s = JSON.parse(Buffer.from(b, "base64url").toString()) as SessionUser;
        if (s.exp > Date.now()) {
          const staff = await resolveStaff(s.uid);
          if (staff) req.user = { ...s, level: staff.role, staffId: staff.id };
        }
      } catch { /* session เสีย = ไม่ล็อกอิน */ }
    }
  }
  next();
}

const requireLevel = (min: Level) => (req: Request, res: Response, next: NextFunction) => {
  if (!req.user) return void res.redirect("/login");
  if (!atLeast(req.user.level, min)) {
    return void res.status(403).send(layout({ title: "ไม่มีสิทธิ์", user: req.user, body: `<div class="card"><h1>ไม่มีสิทธิ์เข้าถึง</h1><p class="muted">หน้านี้สำหรับ ${esc(min)} ขึ้นไป</p></div>` }));
  }
  next();
};

/** ป้องกัน CSRF: ทุก POST ต้องแนบ token ที่ตรงกับ Session */
function csrfCheck(req: Request, res: Response, next: NextFunction) {
  if (req.method !== "POST" || req.path.startsWith("/login") || req.path.startsWith("/auth")) return next();
  const t = typeof req.body?._csrf === "string" ? req.body._csrf : "";
  if (!req.user || !safeEq(t, req.user.csrf)) return void res.status(403).send("คำขอไม่ถูกต้อง (CSRF) กรุณารีเฟรชหน้า");
  next();
}

// ===== web/util.ts =====
const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
const flash = (req: Request) => {
  const t = str(req.query.msg);
  return t ? { text: t, ok: str(req.query.ok) === "1" } : undefined;
};
const back = (res: Response, url: string, text: string, ok: boolean) =>
  res.redirect(`${url}${url.includes("?") ? "&" : "?"}msg=${encodeURIComponent(text)}&ok=${ok ? 1 : 0}`);

/** รัน action แล้ว redirect กลับพร้อมข้อความ (AppError = แจ้งผู้ใช้, อื่น ๆ = log แล้วแจ้งทั่วไป) */
async function act(res: Response, url: string, okText: string, fn: () => Promise<void>) {
  try { await fn(); back(res, url, okText, true); }
  catch (e) {
    if (e instanceof AppError) return void back(res, url, e.message, false);
    logger.error({ err: e }, "web action failed");
    back(res, url, "ระบบขัดข้อง กรุณาลองใหม่", false);
  }
}
const dateInput = (s: string) => (/^\d{4}-\d{2}-\d{2}$/.test(s) ? new Date(s + "T00:00:00+07:00") : null);

// ===== web/auth.ts =====
const authRouter = Router();
const redirectUri = `${config.BASE_URL}/auth/callback`;

// จำกัดความถี่ล็อกอินต่อ IP (ในหน่วยความจำ)
const hits = new Map<string, { n: number; t: number }>();
function limited(ip: string) {
  const now = Date.now(); const h = hits.get(ip);
  if (!h || now - h.t > 60_000) { hits.set(ip, { n: 1, t: now }); return false; }
  return ++h.n > 15;
}

authRouter.get("/login", (req, res) => res.send(loginPage()));

authRouter.get("/login/start", (req, res) => {
  if (limited(req.ip ?? "")) return void res.status(429).send("ลองใหม่ภายหลัง");
  const state = randomBytes(16).toString("hex");
  setStateCookie(res, state);
  const q = new URLSearchParams({ client_id: config.DISCORD_CLIENT_ID, redirect_uri: redirectUri, response_type: "code", scope: "identify", state });
  res.redirect(`https://discord.com/oauth2/authorize?${q}`);
});

authRouter.get("/auth/callback", async (req, res) => {
  try {
    if (limited(req.ip ?? "")) return void res.status(429).send("ลองใหม่ภายหลัง");
    const code = typeof req.query.code === "string" ? req.query.code : "";
    const state = typeof req.query.state === "string" ? req.query.state : "";
    if (!code || !state || state !== parseCookies(req)["jk_state"]) return void res.status(400).send(loginPage("การเข้าสู่ระบบไม่ถูกต้อง กรุณาลองใหม่"));
    res.clearCookie("jk_state", { path: "/" });
    const tok = await fetch("https://discord.com/api/oauth2/token", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ client_id: config.DISCORD_CLIENT_ID, client_secret: config.DISCORD_CLIENT_SECRET, grant_type: "authorization_code", code, redirect_uri: redirectUri }),
    });
    if (!tok.ok) return void res.status(400).send(loginPage("ล็อกอินกับ Discord ไม่สำเร็จ"));
    const { access_token } = (await tok.json()) as { access_token: string };
    const me = await fetch("https://discord.com/api/users/@me", { headers: { Authorization: `Bearer ${access_token}` } });
    if (!me.ok) return void res.status(400).send(loginPage("ดึงข้อมูลผู้ใช้ไม่สำเร็จ"));
    const u = (await me.json()) as { id: string; username: string; global_name?: string };
    const staff = await resolveStaff(u.id);
    if (!staff) return void res.status(403).send(loginPage("บัญชีนี้ไม่มีสิทธิ์เข้าใช้ Dashboard (ให้เจ้าของร้านเพิ่มคุณในหน้า ทีมงาน)"));
    startSession(res, u.id, u.global_name || u.username);
    res.redirect("/");
  } catch (err) {
    logger.error({ err }, "oauth callback failed");
    res.status(500).send(loginPage("เกิดข้อผิดพลาด กรุณาลองใหม่"));
  }
});

authRouter.post("/logout", (req, res) => { endSession(res); res.redirect("/login"); });

// ===== web/routes/overview.ts =====
const overviewRouter = Router();
overviewRouter.get("/", requireLevel("STAFF"), async (req, res) => {
  const u = req.user!; const g = await getGuild();
  const base = { guildId: g.id, deletedAt: null };
  const soon = new Date(Date.now() + 3 * 86400_000);
  const since = new Date(Date.now() - 13 * 86400_000); since.setHours(0, 0, 0, 0);
  const [byStatus, paid, customers, rating, due, recent, last14] = await Promise.all([
    prisma.order.groupBy({ by: ["status"], where: base, _count: { _all: true } }),
    prisma.order.aggregate({ where: { ...base, status: { not: "CANCELLED" } }, _sum: { paidSatang: true } }),
    prisma.user.count({ where: { orders: { some: { guildId: g.id } } } }),
    ratingSummary(),
    prisma.order.findMany({ where: { ...base, dueDate: { lte: soon }, status: { notIn: ["COMPLETED", "CANCELLED"] } }, orderBy: { dueDate: "asc" }, take: 8, include: { customer: true } }),
    prisma.orderStatusHistory.findMany({ where: { order: { guildId: g.id } }, orderBy: { createdAt: "desc" }, take: 10, include: { order: true } }),
    prisma.order.findMany({ where: { ...base, createdAt: { gte: since } }, select: { createdAt: true } }),
  ]);
  const c = (s: string) => byStatus.find((x) => x.status === s)?._count._all ?? 0;
  const total = byStatus.reduce((a, x) => a + x._count._all, 0);
  const inprog = c("CONFIRMED") + c("IN_PROGRESS") + c("WAITING_CUSTOMER") + c("REVISION");
  const days: { label: string; n: number }[] = [];
  for (let k = 13; k >= 0; k--) {
    const d = new Date(Date.now() - k * 86400_000);
    const key = d.toLocaleDateString("en-CA", { timeZone: "Asia/Bangkok" });
    days.push({ label: key.slice(5), n: last14.filter((o) => o.createdAt.toLocaleDateString("en-CA", { timeZone: "Asia/Bangkok" }) === key).length });
  }
  const max = Math.max(1, ...days.map((d) => d.n));
  const stat = (n: string | number, l: string) => `<div class="stat"><b>${esc(n)}</b><span>${esc(l)}</span></div>`;
  res.send(layout({ title: "ภาพรวม", user: u, active: "/", body: `
<h1>ภาพรวมร้าน</h1>
<div class="grid">${stat(total, "ออเดอร์ทั้งหมด")}${stat(c("PENDING"), "ออเดอร์ใหม่ (รอตรวจสอบ)")}${stat(inprog, "กำลังดำเนินการ")}
${stat(c("COMPLETED"), "เสร็จสิ้น")}${stat(c("CANCELLED"), "ยกเลิก")}${stat(customers, "ลูกค้า")}
${stat(rating.count ? `${rating.avg!.toFixed(2)} (${rating.count})` : "-", "คะแนนรีวิวเฉลี่ย")}
${atLeast(u.level, "ADMIN") ? stat(formatBaht(paid._sum.paidSatang ?? 0), "รายรับที่บันทึกไว้") : ""}</div>
<div class="card" style="margin-top:14px"><h2>ออเดอร์ใหม่ 14 วันล่าสุด</h2>
<div class="bars" role="img" aria-label="กราฟจำนวนออเดอร์รายวัน">${days.map((d) => `<div title="${esc(d.label)}: ${d.n}" style="height:${Math.round((d.n / max) * 100)}%"></div>`).join("")}</div>
<div class="muted" style="font-size:12px">${esc(days[0].label)} → ${esc(days[13].label)} (สูงสุด ${max}/วัน)</div></div>
<div class="card"><h2>งานใกล้ถึงกำหนดส่ง (3 วัน)</h2>${due.length ? `<div class="wrap"><table><tr><th>ออเดอร์</th><th>ลูกค้า</th><th>สถานะ</th><th>กำหนดส่ง</th></tr>
${due.map((o) => `<tr><td><a href="/orders/${esc(o.id)}">${esc(o.orderNo)}</a></td><td>${esc(o.customer.username)}</td><td>${orderBadge(o.status, ORDER_STATUS_TH[o.status])}</td><td>${thDay(o.dueDate)}</td></tr>`).join("")}</table></div>` : `<p class="muted">ไม่มีงานใกล้ถึงกำหนด</p>`}</div>
<div class="card"><h2>กิจกรรมล่าสุด</h2>${recent.length ? `<div class="wrap"><table><tr><th>เวลา</th><th>ออเดอร์</th><th>สถานะ</th><th>หมายเหตุ</th></tr>
${recent.map((h) => `<tr><td>${thDate(h.createdAt)}</td><td><a href="/orders/${esc(h.orderId)}">${esc(h.order.orderNo)}</a></td><td>${esc(ORDER_STATUS_TH[h.toStatus])}</td><td>${esc(h.note ?? "")}</td></tr>`).join("")}</table></div>` : `<p class="muted">ยังไม่มีกิจกรรม</p>`}</div>` }));
});

// ===== web/routes/orders.ts =====
const ordersRouter = Router();
ordersRouter.use("/orders", requireLevel("STAFF"));
const ORDERS_PAGE = 20;

ordersRouter.get("/orders", async (req, res) => {
  const u = req.user!; const g = await getGuild();
  const q = str(req.query.q), status = str(req.query.status), from = str(req.query.from), to = str(req.query.to);
  const page = Math.max(1, parseInt(str(req.query.page)) || 1);
  const and: Prisma.OrderWhereInput[] = [];
  if (q) and.push({ OR: [{ orderNo: { contains: q.toUpperCase() } }, { customer: { username: { contains: q, mode: "insensitive" } } }] });
  if (status in ORDER_STATUS_TH) and.push({ status: status as OrderStatus });
  const f = dateInput(from), t = dateInput(to);
  if (f) and.push({ createdAt: { gte: f } });
  if (t) and.push({ createdAt: { lt: new Date(t.getTime() + 86400_000) } });
  if (u.level === "STAFF") and.push({ OR: [{ assigneeId: null }, { assigneeId: u.staffId }] });
  const where: Prisma.OrderWhereInput = { guildId: g.id, deletedAt: null, AND: and };
  const rows = await prisma.order.findMany({ where, orderBy: { createdAt: "desc" }, skip: (page - 1) * ORDERS_PAGE, take: ORDERS_PAGE + 1, include: { customer: true, items: true } });
  const qsBase = `/orders?${new URLSearchParams({ q, status, from, to })}`;
  res.send(layout({ title: "ออเดอร์", user: u, active: "/orders", msg: flash(req), body: `<h1>ออเดอร์</h1>
<form class="card row" method="get" action="/orders">
<div><label for="q">ค้นหา (เลขออเดอร์/ชื่อลูกค้า)</label><input id="q" name="q" value="${esc(q)}"></div>
<div><label for="st">สถานะ</label><select id="st" name="status"><option value="">ทั้งหมด</option>${Object.entries(ORDER_STATUS_TH).map(([k, v]) => `<option value="${k}" ${k === status ? "selected" : ""}>${esc(v)}</option>`).join("")}</select></div>
<div><label for="f">จากวันที่</label><input id="f" type="date" name="from" value="${esc(from)}"></div>
<div><label for="t">ถึงวันที่</label><input id="t" type="date" name="to" value="${esc(to)}"></div><button type="submit">ค้นหา</button></form>
<div class="card wrap">${rows.length ? `<table><tr><th>เลขออเดอร์</th><th>ลูกค้า</th><th>แพ็กเกจ</th><th>สถานะ</th><th>ชำระเงิน</th><th>ราคา</th><th>กำหนดส่ง</th><th>สร้างเมื่อ</th></tr>
${rows.slice(0, ORDERS_PAGE).map((o) => `<tr><td><a href="/orders/${esc(o.id)}">${esc(o.orderNo)}</a></td><td>${esc(o.customer.username)}</td><td>${esc(o.items[0]?.nameSnapshot ?? "-")}</td>
<td>${orderBadge(o.status, ORDER_STATUS_TH[o.status])}</td><td>${payBadge(o.paymentStatus, PAYMENT_STATUS_TH[o.paymentStatus])}</td><td>${o.priceSatang ? formatBaht(o.priceSatang) : "-"}</td><td>${thDay(o.dueDate)}</td><td>${thDate(o.createdAt)}</td></tr>`).join("")}</table>` : `<p class="muted">ไม่พบออเดอร์</p>`}</div>
${pager(qsBase, page, rows.length > ORDERS_PAGE)}` }));
});

ordersRouter.get("/orders/:id", async (req, res) => {
  const u = req.user!; const g = await getGuild();
  const o = await prisma.order.findFirst({
    where: { id: req.params.id, guildId: g.id, deletedAt: null },
    include: { customer: true, items: true, assignee: true, history: { orderBy: { createdAt: "desc" } }, payments: { orderBy: { createdAt: "desc" } }, review: true },
  });
  if (!o || (u.level === "STAFF" && o.assigneeId && o.assigneeId !== u.staffId)) return void res.status(404).send(layout({ title: "ไม่พบ", user: u, body: `<div class="card"><h1>ไม่พบออเดอร์</h1></div>` }));
  const admin = atLeast(u.level, "ADMIN");
  const canManage = admin || o.assigneeId === u.staffId;
  const staff = admin ? await prisma.staffMember.findMany({ where: { guildId: g.id, deletedAt: null }, orderBy: { createdAt: "asc" } }) : [];
  const url = `/orders/${o.id}`;
  const form = (action: string, inner: string, btn: string, cls = "") => `<form method="post" action="${url}/${action}" class="row" style="margin-top:8px">${csrf(u)}${inner}<button class="${cls}" type="submit">${btn}</button></form>`;
  const next = TRANSITIONS[o.status];
  res.send(layout({ title: o.orderNo, user: u, active: "/orders", msg: flash(req), body: `
<p><a href="/orders">← ออเดอร์ทั้งหมด</a></p><h1>${esc(o.orderNo)} ${orderBadge(o.status, ORDER_STATUS_TH[o.status])} ${payBadge(o.paymentStatus, PAYMENT_STATUS_TH[o.paymentStatus])}</h1>
<div class="card"><div class="grid">
<div><span class="muted">ลูกค้า</span><br>${esc(o.customer.username)}<br><span class="muted">${esc(o.customer.discordId)}</span></div>
<div><span class="muted">แพ็กเกจ</span><br>${esc(o.items.map((i) => i.nameSnapshot).join(", "))}</div>
<div><span class="muted">ราคา / ชำระแล้ว</span><br>${o.priceSatang ? formatBaht(o.priceSatang) : "ยังไม่ตั้งราคา"} / ${formatBaht(o.paidSatang)}</div>
<div><span class="muted">งบลูกค้า</span><br>${o.budgetSatang ? formatBaht(o.budgetSatang) : "-"}</div>
<div><span class="muted">กำหนดส่ง</span><br>${thDay(o.dueDate)}</div>
<div><span class="muted">ผู้รับผิดชอบ</span><br>${o.assignee ? esc(o.assignee.discordId) : "ยังไม่มี"}</div></div>
<h2 style="margin-top:14px">รายละเอียดงาน</h2><p style="white-space:pre-wrap">${esc(o.details)}</p>
${o.referenceLinks.length ? `<p>${o.referenceLinks.map((l) => `<a href="${esc(l)}" rel="noopener noreferrer nofollow" target="_blank">${esc(l)}</a>`).join("<br>")}</p>` : ""}
${o.cancelReason ? `<p class="msg err">เหตุผลที่ยกเลิก: ${esc(o.cancelReason)}</p>` : ""}
${o.review ? `<p>รีวิว: ${"★".repeat(o.review.rating)}${"☆".repeat(5 - o.review.rating)} ${esc(o.review.comment ?? "")}${o.review.hidden ? " (ซ่อนอยู่)" : ""}</p>` : ""}</div>
<div class="card"><h2>จัดการงาน</h2>
${!o.assigneeId && !admin ? form("assign", `<input type="hidden" name="assigneeId" value="self">`, "รับงานนี้") : ""}
${canManage ? (next.length ? form("status", `<div><label for="to">เปลี่ยนสถานะเป็น</label><select id="to" name="to">${next.map((s) => `<option value="${s}">${esc(ORDER_STATUS_TH[s])}</option>`).join("")}</select></div>
<div><label for="n">หมายเหตุ (ต้องใส่ถ้ายกเลิก)</label><input id="n" name="note" maxlength="300"></div>`, "บันทึกสถานะ และแจ้งลูกค้า") : `<p class="muted">ออเดอร์นี้เปลี่ยนสถานะต่อไม่ได้</p>`) : `<p class="muted">คุณจัดการได้เฉพาะงานที่รับผิดชอบ (กด "รับงานนี้" ก่อน)</p>`}
${canManage ? form("note", `<div style="flex:1;min-width:240px"><label for="in">หมายเหตุภายใน (ลูกค้าไม่เห็น)</label><input id="in" name="internalNote" maxlength="500" value="${esc(o.internalNote ?? "")}" style="width:100%"></div>`, "บันทึกหมายเหตุ", "ghost") : ""}
${canManage ? form("due", `<div><label for="d">วันส่งงาน</label><input id="d" type="date" name="due" value="${o.dueDate ? o.dueDate.toLocaleDateString("en-CA", { timeZone: "Asia/Bangkok" }) : ""}"></div>`, "บันทึกวันส่ง", "ghost") : ""}
${admin ? form("price", `<div><label for="p">ราคา (บาท)</label><input id="p" name="price" inputmode="decimal" value="${satangToInput(o.priceSatang)}"></div>`, "บันทึกราคา", "ghost") : ""}
${admin ? form("assign", `<div><label for="as">ผู้รับผิดชอบ</label><select id="as" name="assigneeId"><option value="">ไม่กำหนด</option>${staff.map((s) => `<option value="${esc(s.id)}" ${s.id === o.assigneeId ? "selected" : ""}>${esc(s.discordId)} (${esc(s.role)})</option>`).join("")}</select></div>`, "กำหนดผู้รับผิดชอบ", "ghost") : ""}</div>
${admin ? `<div class="card"><h2>บันทึกการชำระเงิน</h2><p class="muted">ทีมงานตรวจยอดเองก่อนบันทึก (ระบบไม่ได้เชื่อมต่อธนาคาร)</p>
${form("payment", `<div><label for="a">ยอดที่ได้รับ (บาท)</label><input id="a" name="amount" inputmode="decimal" required></div><div><label for="pn">หมายเหตุ</label><input id="pn" name="note" maxlength="200"></div>`, "บันทึกยอด")}
${o.payments.length ? `<div class="wrap"><table><tr><th>เวลา</th><th>ยอด</th><th>สถานะ</th></tr>${o.payments.map((p) => `<tr><td>${thDate(p.createdAt)}</td><td>${formatBaht(p.amountSatang)}</td><td>${esc(PAYMENT_STATUS_TH[p.status])}</td></tr>`).join("")}</table></div>` : ""}</div>` : ""}
<div class="card"><h2>ประวัติการเปลี่ยนแปลง</h2><div class="wrap"><table><tr><th>เวลา</th><th>จาก</th><th>เป็น</th><th>โดย (Discord ID)</th><th>หมายเหตุ</th></tr>
${o.history.map((h) => `<tr><td>${thDate(h.createdAt)}</td><td>${h.fromStatus ? esc(ORDER_STATUS_TH[h.fromStatus]) : "-"}</td><td>${esc(ORDER_STATUS_TH[h.toStatus])}</td><td>${esc(h.actorDiscordId)}</td><td>${esc(h.note ?? "")}</td></tr>`).join("")}</table></div></div>` }));
});

/** ตรวจสิทธิ์ฝั่งเซิร์ฟเวอร์ก่อนทุก action: ADMIN+ จัดการได้ทั้งหมด, STAFF เฉพาะงานที่ตนรับผิดชอบ */
async function authorize(req: any, orderId: string, needAdmin = false) {
  const u = req.user!; const g = await getGuild();
  const o = await prisma.order.findFirst({ where: { id: orderId, guildId: g.id, deletedAt: null } });
  if (!o) throw new AppError("NOT_FOUND", "ไม่พบออเดอร์");
  const admin = atLeast(u.level, "ADMIN");
  if (needAdmin && !admin) throw new AppError("FORBIDDEN", "ต้องเป็นแอดมินขึ้นไป");
  if (!admin && o.assigneeId !== u.staffId) throw new AppError("FORBIDDEN", "คุณไม่ได้รับผิดชอบงานนี้");
  return u;
}

ordersRouter.post("/orders/:id/status", async (req, res) => {
  const url = `/orders/${req.params.id}`;
  await act(res, url, "เปลี่ยนสถานะแล้ว และแจ้งลูกค้าแล้ว", async () => {
    const u = await authorize(req, req.params.id);
    const to = str(req.body.to) as OrderStatus;
    if (!(to in ORDER_STATUS_TH)) throw new AppError("BAD", "สถานะไม่ถูกต้อง");
    await changeStatus({ orderId: req.params.id, to, actorDiscordId: u.uid, note: str(req.body.note).slice(0, 300) });
  });
});
ordersRouter.post("/orders/:id/note", async (req, res) => {
  await act(res, `/orders/${req.params.id}`, "บันทึกแล้ว", async () => {
    const u = await authorize(req, req.params.id);
    await updateOrder(req.params.id, u.uid, { internalNote: str(req.body.internalNote).slice(0, 500) || null });
  });
});
ordersRouter.post("/orders/:id/due", async (req, res) => {
  await act(res, `/orders/${req.params.id}`, "บันทึกวันส่งงานแล้ว", async () => {
    const u = await authorize(req, req.params.id);
    const raw = str(req.body.due); const d = raw ? dateInput(raw) : null;
    if (raw && !d) throw new AppError("BAD", "วันที่ไม่ถูกต้อง");
    await updateOrder(req.params.id, u.uid, { dueDate: d });
  });
});
ordersRouter.post("/orders/:id/price", async (req, res) => {
  await act(res, `/orders/${req.params.id}`, "บันทึกราคาแล้ว", async () => {
    const u = await authorize(req, req.params.id, true);
    const p = bahtToSatang(str(req.body.price));
    if (p === null) throw new AppError("BAD", "ราคาไม่ถูกต้อง");
    await updateOrder(req.params.id, u.uid, { priceSatang: p });
  });
});
ordersRouter.post("/orders/:id/assign", async (req, res) => {
  await act(res, `/orders/${req.params.id}`, "บันทึกผู้รับผิดชอบแล้ว", async () => {
    const u = req.user!; const g = await getGuild();
    const o = await prisma.order.findFirst({ where: { id: req.params.id, guildId: g.id, deletedAt: null } });
    if (!o) throw new AppError("NOT_FOUND", "ไม่พบออเดอร์");
    const v = str(req.body.assigneeId);
    if (atLeast(u.level, "ADMIN")) {
      await updateOrder(o.id, u.uid, { assigneeId: v === "self" ? u.staffId : v || null });
    } else {
      // STAFF: รับงานที่ยังไม่มีผู้รับผิดชอบได้เท่านั้น
      if (v !== "self" || o.assigneeId) throw new AppError("FORBIDDEN", "รับได้เฉพาะงานที่ยังไม่มีผู้รับผิดชอบ");
      await updateOrder(o.id, u.uid, { assigneeId: u.staffId });
    }
  });
});
ordersRouter.post("/orders/:id/payment", async (req, res) => {
  await act(res, `/orders/${req.params.id}`, "บันทึกยอดแล้ว", async () => {
    const u = await authorize(req, req.params.id, true);
    const a = bahtToSatang(str(req.body.amount));
    if (a === null) throw new AppError("BAD", "ยอดเงินไม่ถูกต้อง");
    await recordPayment(req.params.id, a, u.uid, str(req.body.note).slice(0, 200));
  });
});

// ===== web/routes/packages.ts =====
const packagesRouter = Router();
packagesRouter.use("/packages", requireLevel("ADMIN"));

const pkgSchema = z.object({
  name: z.string().trim().min(1, "ใส่ชื่อแพ็กเกจ").max(80),
  description: z.string().trim().max(500).optional().transform((v) => v || null),
  price: z.string().trim().default("0"),
  etaDays: z.string().trim().optional().transform((v) => (v ? parseInt(v, 10) : null)).pipe(z.number().int().min(1).max(365).nullable()),
  coverUrl: z.string().trim().optional().transform((v) => v || null).pipe(z.string().url().startsWith("https://", "ภาพปกต้องเป็นลิงก์ https://").nullable()),
  inclusions: z.string().optional().transform((v) => (v ?? "").split("\n").map((x) => x.trim()).filter(Boolean).slice(0, 15)),
  sortOrder: z.string().trim().optional().transform((v) => (v ? parseInt(v, 10) : 0)).pipe(z.number().int().min(0).max(9999)),
});
function parse(body: any) {
  const r = pkgSchema.safeParse(body);
  if (!r.success) throw new AppError("BAD", r.error.issues[0].message);
  const price = bahtToSatang(r.data.price);
  if (price === null) throw new AppError("BAD", "ราคาไม่ถูกต้อง");
  return { ...r.data, priceSatang: price, isCustom: body.isCustom === "on", active: body.active === "on" };
}
async function defaultProduct(guildId: string) {
  return (await prisma.product.findFirst({ where: { guildId, deletedAt: null }, orderBy: { createdAt: "asc" } }))
    ?? prisma.product.create({ data: { guildId, name: "บริการตกแต่งเซิร์ฟเวอร์" } });
}
const fields = (p?: { name: string; description: string | null; priceSatang: number; etaDays: number | null; coverUrl: string | null; inclusions: string[]; sortOrder: number; isCustom: boolean; active: boolean }) => `
<div class="row"><div><label>ชื่อแพ็กเกจ</label><input name="name" required maxlength="80" value="${esc(p?.name)}"></div>
<div><label>ราคา (บาท)</label><input name="price" inputmode="decimal" value="${p ? satangToInput(p.priceSatang) : "0"}"></div>
<div><label>ระยะเวลา (วัน)</label><input name="etaDays" inputmode="numeric" value="${esc(p?.etaDays ?? "")}"></div>
<div><label>ลำดับแสดง</label><input name="sortOrder" inputmode="numeric" value="${esc(p?.sortOrder ?? 0)}"></div></div>
<label>รายละเอียด</label><input name="description" maxlength="500" style="width:100%" value="${esc(p?.description)}">
<label>ภาพปก (ลิงก์ https://)</label><input name="coverUrl" style="width:100%" value="${esc(p?.coverUrl)}">
<label>สิ่งที่ลูกค้าจะได้รับ (บรรทัดละข้อ)</label><textarea name="inclusions">${esc(p?.inclusions.join("\n"))}</textarea>
<label><input type="checkbox" name="isCustom" ${p?.isCustom ? "checked" : ""}> แพ็กเกจกำหนดเอง (ราคาตามตกลง)</label>
<label><input type="checkbox" name="active" ${!p || p.active ? "checked" : ""}> เปิดขาย</label>`;

packagesRouter.get("/packages", async (req, res) => {
  const u = req.user!; const g = await getGuild();
  const list = await prisma.productPackage.findMany({ where: { deletedAt: null, product: { guildId: g.id, deletedAt: null } }, orderBy: [{ sortOrder: "asc" }, { createdAt: "asc" }] });
  res.send(layout({ title: "แพ็กเกจ", user: u, active: "/packages", msg: flash(req), body: `<h1>แพ็กเกจบริการ</h1>
<div class="card"><h2>เพิ่มแพ็กเกจ</h2><form method="post" action="/packages">${csrf(u)}${fields()}<p><button type="submit">เพิ่มแพ็กเกจ</button></p></form></div>
${list.length ? list.map((p) => `<div class="card"><details><summary>${esc(p.name)} — ${p.isCustom ? "ตามตกลง" : formatBaht(p.priceSatang)} ${p.active ? badge("เปิดขาย", "ok") : badge("ปิดขาย", "warn")}</summary>
<form method="post" action="/packages/${esc(p.id)}">${csrf(u)}${fields(p)}<div class="row" style="margin-top:10px"><button type="submit">บันทึก</button></div></form>
<form method="post" action="/packages/${esc(p.id)}/delete" onsubmit="return confirm('ลบแพ็กเกจนี้? (ออเดอร์เดิมยังเก็บไว้)')" style="margin-top:8px">${csrf(u)}<button class="danger" type="submit">ลบแพ็กเกจ</button></form></details></div>`).join("") : `<p class="muted">ยังไม่มีแพ็กเกจ</p>`}` }));
});

packagesRouter.post("/packages", async (req, res) => {
  await act(res, "/packages", "เพิ่มแพ็กเกจแล้ว", async () => {
    const d = parse(req.body); const g = await getGuild(); const prod = await defaultProduct(g.id);
    const { price: _p, ...data } = d;
    const p = await prisma.productPackage.create({ data: { ...data, productId: prod.id } });
    await audit(prisma, g.id, req.user!.uid, "package.create", "ProductPackage", p.id, undefined, { name: p.name, priceSatang: p.priceSatang });
  });
});
packagesRouter.post("/packages/:id", async (req, res) => {
  await act(res, "/packages", "บันทึกแพ็กเกจแล้ว", async () => {
    const d = parse(req.body); const g = await getGuild();
    const old = await prisma.productPackage.findFirst({ where: { id: req.params.id, deletedAt: null, product: { guildId: g.id } } });
    if (!old) throw new AppError("NOT_FOUND", "ไม่พบแพ็กเกจ");
    const { price: _p, ...data } = d;
    await prisma.productPackage.update({ where: { id: old.id }, data });
    await audit(prisma, g.id, req.user!.uid, "package.update", "ProductPackage", old.id,
      { name: old.name, priceSatang: old.priceSatang, active: old.active }, { name: data.name, priceSatang: data.priceSatang, active: data.active });
  });
});
packagesRouter.post("/packages/:id/delete", async (req, res) => {
  await act(res, "/packages", "ลบแพ็กเกจแล้ว", async () => {
    const g = await getGuild();
    const r = await prisma.productPackage.updateMany({ where: { id: req.params.id, deletedAt: null, product: { guildId: g.id } }, data: { deletedAt: new Date(), active: false } });
    if (r.count !== 1) throw new AppError("NOT_FOUND", "ไม่พบแพ็กเกจ");
    await audit(prisma, g.id, req.user!.uid, "package.delete", "ProductPackage", req.params.id);
  });
});

// ===== web/routes/people.ts =====
const peopleRouter = Router();
peopleRouter.use(["/customers", "/reviews"], requireLevel("ADMIN"));
const PEOPLE_PAGE = 25;

peopleRouter.get("/customers", async (req, res) => {
  const u = req.user!; const g = await getGuild();
  const q = str(req.query.q); const page = Math.max(1, parseInt(str(req.query.page)) || 1);
  const where: Prisma.UserWhereInput = { orders: { some: { guildId: g.id } }, ...(q ? { OR: [{ username: { contains: q, mode: "insensitive" } }, { discordId: { contains: q } }] } : {}) };
  const users = await prisma.user.findMany({ where, orderBy: { createdAt: "desc" }, skip: (page - 1) * PEOPLE_PAGE, take: PEOPLE_PAGE + 1, include: { _count: { select: { reviews: true } } } });
  const ids = users.map((x) => x.id);
  const [all, done] = await Promise.all([
    prisma.order.groupBy({ by: ["customerId"], where: { guildId: g.id, deletedAt: null, customerId: { in: ids } }, _count: { _all: true }, _sum: { paidSatang: true } }),
    prisma.order.groupBy({ by: ["customerId"], where: { guildId: g.id, deletedAt: null, status: "COMPLETED", customerId: { in: ids } }, _count: { _all: true } }),
  ]);
  res.send(layout({ title: "ลูกค้า", user: u, active: "/customers", msg: flash(req), body: `<h1>ลูกค้า</h1>
<form class="card row" method="get"><div><label for="q">ค้นหา (ชื่อ/Discord ID)</label><input id="q" name="q" value="${esc(q)}"></div><button type="submit">ค้นหา</button></form>
<div class="card wrap"><table><tr><th>Discord</th><th>Discord ID</th><th>ออเดอร์</th><th>เสร็จสิ้น</th><th>ยอดชำระที่บันทึก</th><th>รีวิว</th><th>สร้างเมื่อ</th></tr>
${users.slice(0, PEOPLE_PAGE).map((c) => `<tr><td>${esc(c.username)}</td><td>${esc(c.discordId)}</td><td>${all.find((x) => x.customerId === c.id)?._count._all ?? 0}</td><td>${done.find((x) => x.customerId === c.id)?._count._all ?? 0}</td>
<td>${formatBaht(all.find((x) => x.customerId === c.id)?._sum.paidSatang ?? 0)}</td><td>${c._count.reviews}</td><td>${thDate(c.createdAt)}</td></tr>`).join("") || `<tr><td colspan="7" class="muted">ยังไม่มีลูกค้า</td></tr>`}</table></div>
${pager(`/customers?q=${encodeURIComponent(q)}`, page, users.length > PEOPLE_PAGE)}` }));
});

peopleRouter.get("/reviews", async (req, res) => {
  const u = req.user!; const g = await getGuild();
  const rating = parseInt(str(req.query.rating)) || 0; const page = Math.max(1, parseInt(str(req.query.page)) || 1);
  const list = await prisma.review.findMany({
    where: { guildId: g.id, ...(rating >= 1 && rating <= 5 ? { rating } : {}) }, orderBy: { createdAt: "desc" },
    skip: (page - 1) * PEOPLE_PAGE, take: PEOPLE_PAGE + 1, include: { order: true, customer: true },
  });
  res.send(layout({ title: "รีวิว", user: u, active: "/reviews", msg: flash(req), body: `<h1>รีวิว</h1>
<form class="card row" method="get"><div><label for="r">กรองคะแนน</label><select id="r" name="rating"><option value="">ทั้งหมด</option>${[5, 4, 3, 2, 1].map((n) => `<option value="${n}" ${n === rating ? "selected" : ""}>${n} ดาว</option>`).join("")}</select></div><button type="submit">กรอง</button></form>
${list.slice(0, PEOPLE_PAGE).map((r) => `<div class="card"><b>${"★".repeat(r.rating)}${"☆".repeat(5 - r.rating)}</b> ${r.hidden ? badge("ซ่อนอยู่", "warn") : ""}
<span class="muted"> ${esc(r.customer.username)} · <a href="/orders/${esc(r.orderId)}">${esc(r.order.orderNo)}</a> · ${thDate(r.createdAt)}</span>
<p style="white-space:pre-wrap">${esc(r.comment ?? "(ไม่มีข้อความ)")}</p>${r.hidden ? `<p class="muted">เหตุผลที่ซ่อน: ${esc(r.hiddenReason ?? "")}</p>` : ""}
<form method="post" action="/reviews/${esc(r.id)}/${r.hidden ? "unhide" : "hide"}" class="row">${csrf(u)}
${r.hidden ? "" : `<div><label>เหตุผลที่ซ่อน</label><input name="reason" required maxlength="200"></div>`}
<button class="${r.hidden ? "ghost" : "danger"}" type="submit">${r.hidden ? "เลิกซ่อน" : "ซ่อนรีวิว"}</button></form></div>`).join("") || `<p class="muted">ยังไม่มีรีวิว</p>`}
${pager(`/reviews?rating=${rating || ""}`, page, list.length > PEOPLE_PAGE)}` }));
});

peopleRouter.post("/reviews/:id/:op", async (req, res) => {
  await act(res, "/reviews", "บันทึกแล้ว", async () => {
    const g = await getGuild(); const hide = req.params.op === "hide";
    if (!hide && req.params.op !== "unhide") throw new AppError("BAD", "คำสั่งไม่ถูกต้อง");
    const reason = str(req.body.reason).slice(0, 200);
    if (hide && !reason) throw new AppError("BAD", "ต้องระบุเหตุผล");
    const r = await prisma.review.updateMany({
      where: { id: req.params.id, guildId: g.id },
      data: hide ? { hidden: true, hiddenReason: reason, hiddenByDiscordId: req.user!.uid } : { hidden: false, hiddenReason: null, hiddenByDiscordId: null },
    });
    if (r.count !== 1) throw new AppError("NOT_FOUND", "ไม่พบรีวิว");
    await audit(prisma, g.id, req.user!.uid, hide ? "review.hide" : "review.unhide", "Review", req.params.id, undefined, { reason });
  });
});

// ===== web/routes/admin.ts =====
const adminRouter = Router();
adminRouter.use(["/settings", "/audit"], requireLevel("ADMIN"));
adminRouter.use("/staff", requireLevel("OWNER"));
const snowflake = /^\d{15,25}$/;

adminRouter.get("/settings", async (req, res) => {
  const u = req.user!; const { settings: s } = await getSettings();
  const ch = (name: string, label: string, v: string | null) => `<div><label for="${name}">${label} (Channel ID)</label><input id="${name}" name="${name}" inputmode="numeric" value="${esc(v)}" placeholder="เว้นว่าง = ไม่ใช้"></div>`;
  res.send(layout({ title: "ตั้งค่า", user: u, active: "/settings", msg: flash(req), body: `<h1>ตั้งค่าร้าน</h1>
<form method="post" action="/settings" class="card">${csrf(u)}
<h2>สถานะร้าน</h2><label><input type="checkbox" name="shopOpen" ${s.shopOpen ? "checked" : ""}> เปิดรับออเดอร์</label>
<h2 style="margin-top:14px">ห้อง Discord</h2><p class="muted">เปิด Developer Mode ใน Discord แล้วคลิกขวาที่ห้อง > Copy Channel ID</p>
<div class="row">${ch("orderChannelId", "ห้องแจ้งออเดอร์ใหม่ (ทีมงาน)", s.orderChannelId)}${ch("logChannelId", "ห้อง Log", s.logChannelId)}${ch("reviewChannelId", "ห้องรีวิว", s.reviewChannelId)}</div>
<h2 style="margin-top:14px">หน้าตา</h2><div class="row"><div><label for="c">สี Embed (เช่น #8B0000)</label><input id="c" name="embedColor" value="#${s.embedColor.toString(16).padStart(6, "0")}"></div>
<div><label for="f">Footer</label><input id="f" name="footerText" maxlength="100" value="${esc(s.footerText)}"></div></div>
<p><button type="submit">บันทึกการตั้งค่า</button></p></form>` }));
});
adminRouter.post("/settings", async (req, res) => {
  await act(res, "/settings", "บันทึกการตั้งค่าแล้ว", async () => {
    const { guild, settings } = await getSettings();
    const data: Record<string, unknown> = { shopOpen: req.body.shopOpen === "on", footerText: str(req.body.footerText).slice(0, 100) || null };
    for (const k of ["orderChannelId", "logChannelId", "reviewChannelId"]) {
      const v = str(req.body[k]);
      if (v && !snowflake.test(v)) throw new AppError("BAD", `${k} ต้องเป็นตัวเลข ID`);
      data[k] = v || null;
    }
    const col = str(req.body.embedColor).replace(/^#/, "");
    if (!/^[0-9a-fA-F]{6}$/.test(col)) throw new AppError("BAD", "สี Embed ไม่ถูกต้อง (ตัวอย่าง #8B0000)");
    data.embedColor = parseInt(col, 16);
    await prisma.guildSettings.update({ where: { guildId: guild.id }, data });
    await audit(prisma, guild.id, req.user!.uid, "settings.update", "GuildSettings", settings.id, settings, data);
  });
});

adminRouter.get("/staff", async (req, res) => {
  const u = req.user!; const g = await getGuild();
  const list = await prisma.staffMember.findMany({ where: { guildId: g.id, deletedAt: null }, orderBy: { createdAt: "asc" } });
  res.send(layout({ title: "ทีมงาน", user: u, active: "/staff", msg: flash(req), body: `<h1>ทีมงาน</h1>
<form method="post" action="/staff" class="card row">${csrf(u)}<div><label for="d">Discord User ID</label><input id="d" name="discordId" inputmode="numeric" required></div>
<div><label for="r">ระดับสิทธิ์</label><select id="r" name="role"><option value="STAFF">ทีมงาน (STAFF)</option><option value="ADMIN">แอดมิน (ADMIN)</option></select></div><button type="submit">เพิ่ม/แก้ไขสิทธิ์</button></form>
<div class="card wrap"><table><tr><th>Discord ID</th><th>ระดับ</th><th></th></tr>${list.map((s) => `<tr><td>${esc(s.discordId)}</td><td>${badge(s.role)}</td>
<td>${s.discordId === config.OWNER_DISCORD_ID ? `<span class="muted">เจ้าของร้าน</span>` : `<form method="post" action="/staff/${esc(s.id)}/remove" onsubmit="return confirm('ถอดสิทธิ์คนนี้?')">${csrf(u)}<button class="danger" type="submit">ถอดสิทธิ์</button></form>`}</td></tr>`).join("")}</table></div>` }));
});
adminRouter.post("/staff", async (req, res) => {
  await act(res, "/staff", "บันทึกทีมงานแล้ว", async () => {
    const g = await getGuild(); const id = str(req.body.discordId); const role = str(req.body.role);
    if (!snowflake.test(id)) throw new AppError("BAD", "Discord ID ไม่ถูกต้อง");
    if (role !== "STAFF" && role !== "ADMIN") throw new AppError("BAD", "ระดับสิทธิ์ไม่ถูกต้อง");
    if (id === config.OWNER_DISCORD_ID) throw new AppError("BAD", "แก้สิทธิ์เจ้าของร้านไม่ได้");
    await prisma.staffMember.upsert({ where: { guildId_discordId: { guildId: g.id, discordId: id } }, update: { role, deletedAt: null }, create: { guildId: g.id, discordId: id, role } });
    await audit(prisma, g.id, req.user!.uid, "staff.set", "StaffMember", id, undefined, { role });
  });
});
adminRouter.post("/staff/:id/remove", async (req, res) => {
  await act(res, "/staff", "ถอดสิทธิ์แล้ว", async () => {
    const g = await getGuild();
    const s = await prisma.staffMember.findFirst({ where: { id: req.params.id, guildId: g.id, deletedAt: null } });
    if (!s || s.discordId === config.OWNER_DISCORD_ID) throw new AppError("BAD", "ถอดสิทธิ์คนนี้ไม่ได้");
    await prisma.staffMember.update({ where: { id: s.id }, data: { deletedAt: new Date() } });
    await audit(prisma, g.id, req.user!.uid, "staff.remove", "StaffMember", s.discordId);
  });
});

adminRouter.get("/audit", async (req, res) => {
  const g = await getGuild();
  const logs = await prisma.auditLog.findMany({ where: { guildId: g.id }, orderBy: { createdAt: "desc" }, take: 100 });
  const j = (v: unknown) => (v == null ? "" : esc(JSON.stringify(v)).slice(0, 200));
  res.send(layout({ title: "Audit Log", user: req.user!, active: "/audit", body: `<h1>Audit Log (100 รายการล่าสุด)</h1><div class="card wrap"><table>
<tr><th>เวลา</th><th>ผู้ทำ (Discord ID)</th><th>การกระทำ</th><th>เป้าหมาย</th><th>ก่อน</th><th>หลัง</th></tr>
${logs.map((l) => `<tr><td>${thDate(l.createdAt)}</td><td>${esc(l.actorDiscordId)}</td><td>${esc(l.action)}</td><td>${esc(l.entity)} ${esc(l.entityId ?? "")}</td><td>${j(l.before)}</td><td>${j(l.after)}</td></tr>`).join("") || `<tr><td colspan="6" class="muted">ยังไม่มีรายการ</td></tr>`}</table></div>` }));
});

// ===== web/server.ts =====
function startWeb() {
  const app = express();
  app.set("trust proxy", 1); // ใช้หลัง Reverse Proxy ของโฮสต์ (Railway ฯลฯ)
  app.disable("x-powered-by");
  app.use((req, res, next) => {
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("X-Frame-Options", "DENY");
    res.setHeader("Referrer-Policy", "same-origin");
    res.setHeader("Cache-Control", "no-store");
    next();
  });
  app.get("/health", async (_req, res) => {
    try { await prisma.$queryRaw`SELECT 1`; res.json({ ok: true }); } catch { res.status(503).json({ ok: false }); }
  });
  app.use(express.urlencoded({ extended: false, limit: "50kb" }));
  app.use(loadUser);
  app.use(csrfCheck);
  app.use(authRouter);
  app.use(overviewRouter, ordersRouter, packagesRouter, peopleRouter, adminRouter);
  app.use((req, res) => res.status(404).send(layout({ title: "ไม่พบหน้า", user: req.user, body: `<div class="card"><h1>ไม่พบหน้านี้</h1></div>` })));
  app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    logger.error({ err }, "web error"); // ไม่แสดง Stack Trace ให้ผู้ใช้
    res.status(500).send("เกิดข้อผิดพลาดภายในระบบ");
  });
  return app.listen(config.PORT, () => logger.info({ port: config.PORT }, "Dashboard พร้อมใช้งาน"));
}

// ===== bot/types.ts =====
interface Command {
  data: SlashCommandBuilder | SlashCommandOptionsOnlyBuilder;
  description: string; // แสดงใน /help
  minRole?: Level;
  execute(i: ChatInputCommandInteraction): Promise<void>;
}
interface Handler<T> { prefix: string; execute(i: T, args: string[]): Promise<void> }
type SelectHandler = Handler<StringSelectMenuInteraction>;
type ModalHandler = Handler<ModalSubmitInteraction>;

// ===== bot/commands/basic.ts =====
const ping: Command = {
  data: new SlashCommandBuilder().setName("ping").setDescription("ตรวจสอบความหน่วงของบอท"),
  description: "ตรวจสอบความหน่วงของบอท",
  async execute(i) { await i.reply({ content: `Pong — ${Math.round(i.client.ws.ping)} ms`, ephemeral: true }); },
};

const botinfo: Command = {
  data: new SlashCommandBuilder().setName("botinfo").setDescription("สถานะของบอท"),
  description: "ดูสถานะบอทและการเชื่อมต่อฐานข้อมูล",
  async execute(i) {
    let db = "ปกติ";
    try { await prisma.$queryRaw`SELECT 1`; } catch { db = "เชื่อมต่อไม่ได้"; }
    const up = Math.floor(process.uptime());
    await i.reply({ ephemeral: true, embeds: [brandEmbed().setTitle("JUKKINGDOM BOT").addFields(
      { name: "Uptime", value: `${Math.floor(up / 3600)} ชม. ${Math.floor((up % 3600) / 60)} นาที`, inline: true },
      { name: "Ping", value: `${Math.round(i.client.ws.ping)} ms`, inline: true },
      { name: "ฐานข้อมูล", value: db, inline: true },
    )] });
  },
};

const dashboard: Command = {
  data: new SlashCommandBuilder().setName("dashboard").setDescription("ลิงก์หน้าจัดการร้าน (ทีมงาน)"),
  description: "ลิงก์ไปหน้า Dashboard จัดการร้าน",
  minRole: "STAFF",
  async execute(i) { await i.reply({ content: config.BASE_URL, ephemeral: true }); },
};

const help: Command = {
  data: new SlashCommandBuilder().setName("help").setDescription("รายการคำสั่งที่คุณใช้ได้"),
  description: "แสดงคำสั่งที่คุณมีสิทธิ์ใช้งาน",
  async execute(i) {
    const level = i.inCachedGuild() ? await getBotLevel(i.member) : "CUSTOMER";
    const lines = [...commands.values()].filter((c) => rank[level] >= rank[c.minRole ?? "CUSTOMER"])
      .map((c) => `**/${c.data.name}** — ${c.description}`);
    await i.reply({ embeds: [brandEmbed().setTitle("คำสั่งทั้งหมด").setDescription(lines.join("\n"))], ephemeral: true });
  },
};

// ===== bot/commands/shopcmds.ts =====
async function activePackages() {
  const g = await getGuild();
  return prisma.productPackage.findMany({
    where: { active: true, deletedAt: null, product: { guildId: g.id, active: true, deletedAt: null } },
    orderBy: [{ product: { sortOrder: "asc" } }, { sortOrder: "asc" }], take: 25,
  });
}

const packages: Command = {
  data: new SlashCommandBuilder().setName("packages").setDescription("ดูแพ็กเกจและราคา"),
  description: "ดูแพ็กเกจและราคาบริการของร้าน",
  async execute(i) {
    const list = await activePackages();
    if (!list.length) return void (await i.reply({ embeds: [errorEmbed("ยังไม่มีแพ็กเกจที่เปิดขาย")], ephemeral: true }));
    const e = brandEmbed().setTitle("แพ็กเกจบริการ").setDescription("สั่งงานด้วยคำสั่ง /order");
    for (const p of list) e.addFields({
      name: `${p.name} — ${p.isCustom ? "ตามตกลง" : formatBaht(p.priceSatang)}`,
      value: [p.description ?? "", p.etaDays ? `ระยะเวลาประมาณ ${p.etaDays} วัน` : "", ...p.inclusions.map((x) => `• ${x}`)]
        .filter(Boolean).join("\n").slice(0, 1024) || "-",
    });
    await i.reply({ embeds: [e] });
  },
};

const order: Command = {
  data: new SlashCommandBuilder().setName("order").setDescription("สั่งงานกับ JUKKINGDOM"),
  description: "เลือกแพ็กเกจและกรอกรายละเอียดเพื่อสั่งงาน",
  async execute(i) {
    const { settings } = await getSettings();
    if (!settings.shopOpen) return void (await i.reply({ embeds: [errorEmbed("ขณะนี้ร้านปิดรับออเดอร์ชั่วคราว")], ephemeral: true }));
    const list = await activePackages();
    if (!list.length) return void (await i.reply({ embeds: [errorEmbed("ยังไม่มีแพ็กเกจที่เปิดขาย")], ephemeral: true }));
    const menu = new StringSelectMenuBuilder().setCustomId("order:pick").setPlaceholder("เลือกแพ็กเกจ")
      .addOptions(list.map((p) => ({ label: p.name.slice(0, 100), description: p.isCustom ? "ตามตกลง" : formatBaht(p.priceSatang), value: p.id })));
    await i.reply({ content: "เลือกแพ็กเกจที่ต้องการ", components: [new ActionRowBuilder<StringSelectMenuBuilder>().addComponents(menu)], ephemeral: true });
  },
};

const myorders: Command = {
  data: new SlashCommandBuilder().setName("myorders").setDescription("ดูออเดอร์ของฉัน"),
  description: "ดูออเดอร์และสถานะของตัวคุณเอง",
  async execute(i) {
    const orders = await listOrdersForCustomer(i.user.id);
    if (!orders.length) return void (await i.reply({ content: "คุณยังไม่มีออเดอร์", ephemeral: true }));
    const e = brandEmbed().setTitle("ออเดอร์ของฉัน");
    for (const o of orders) e.addFields({
      name: o.orderNo,
      value: `สถานะ: ${ORDER_STATUS_TH[o.status]}\nการชำระเงิน: ${PAYMENT_STATUS_TH[o.paymentStatus]}\nราคา: ${formatBaht(o.priceSatang)}`,
    });
    await i.reply({ embeds: [e], ephemeral: true });
  },
};

const track: Command = {
  data: new SlashCommandBuilder().setName("track").setDescription("ติดตามสถานะออเดอร์")
    .addStringOption((o) => o.setName("order_no").setDescription("เลขออเดอร์ เช่น JK-ABC123").setRequired(true)),
  description: "ติดตามสถานะออเดอร์ด้วยเลขออเดอร์",
  async execute(i) {
    const no = i.options.getString("order_no", true).trim().toUpperCase();
    const g = await getGuild();
    const staff = i.inCachedGuild() && atLeast(await getBotLevel(i.member), "STAFF");
    // ลูกค้าเห็นเฉพาะของตัวเอง ทีมงานเห็นได้ทั้งหมด
    const o = await prisma.order.findFirst({
      where: { orderNo: no, guildId: g.id, deletedAt: null, ...(staff ? {} : { customer: { discordId: i.user.id } }) },
      include: { history: { orderBy: { createdAt: "desc" }, take: 5 } },
    });
    if (!o) return void (await i.reply({ embeds: [errorEmbed("ไม่พบออเดอร์นี้")], ephemeral: true }));
    await i.reply({ ephemeral: true, embeds: [brandEmbed().setTitle(`ออเดอร์ ${o.orderNo}`).addFields(
      { name: "สถานะ", value: ORDER_STATUS_TH[o.status], inline: true },
      { name: "การชำระเงิน", value: PAYMENT_STATUS_TH[o.paymentStatus], inline: true },
      { name: "ราคา", value: o.priceSatang ? formatBaht(o.priceSatang) : "รอประเมิน", inline: true },
      { name: "ความคืบหน้าล่าสุด", value: o.history.map((h) => `${thDate(h.createdAt)} — ${ORDER_STATUS_TH[h.toStatus]}`).join("\n") || "-" },
    )] });
  },
};

const review: Command = {
  data: new SlashCommandBuilder().setName("review").setDescription("รีวิวงานที่เสร็จสิ้นแล้ว")
    .addStringOption((o) => o.setName("order_no").setDescription("เลขออเดอร์").setRequired(true))
    .addIntegerOption((o) => o.setName("rating").setDescription("คะแนน 1-5").setMinValue(1).setMaxValue(5).setRequired(true))
    .addStringOption((o) => o.setName("comment").setDescription("ข้อความรีวิว").setMaxLength(500)),
  description: "ให้คะแนนและรีวิวออเดอร์ที่เสร็จสิ้นแล้ว",
  async execute(i) {
    try {
      await createReview({ orderNo: i.options.getString("order_no", true), customerDiscordId: i.user.id,
        rating: i.options.getInteger("rating", true), comment: i.options.getString("comment") ?? undefined });
      await i.reply({ content: "ขอบคุณสำหรับรีวิวครับ", ephemeral: true });
    } catch (e) {
      if (e instanceof AppError) return void (await i.reply({ embeds: [errorEmbed(e.message)], ephemeral: true }));
      throw e;
    }
  },
};

const reviews: Command = {
  data: new SlashCommandBuilder().setName("reviews").setDescription("ดูรีวิวล่าสุดและคะแนนเฉลี่ย"),
  description: "ดูรีวิวล่าสุดและคะแนนเฉลี่ยของร้าน",
  async execute(i) {
    const g = await getGuild();
    const [sum, list] = await Promise.all([
      ratingSummary(),
      prisma.review.findMany({ where: { guildId: g.id, hidden: false }, orderBy: { createdAt: "desc" }, take: 5 }),
    ]);
    const e = brandEmbed().setTitle("รีวิวจากลูกค้า")
      .setDescription(sum.count ? `คะแนนเฉลี่ย **${sum.avg!.toFixed(2)}** / 5 (${sum.count} รีวิว)` : "ยังไม่มีรีวิว");
    for (const r of list) e.addFields({ name: "★".repeat(r.rating) + "☆".repeat(5 - r.rating), value: r.comment || "-" });
    await i.reply({ embeds: [e] });
  },
};

// ===== bot/commands/admin.ts =====
const setup: Command = {
  data: new SlashCommandBuilder().setName("setup").setDescription("ตั้งค่าห้องของร้าน (แอดมิน)")
    .addChannelOption((o) => o.setName("orders").setDescription("ห้องแจ้งออเดอร์ใหม่ (ทีมงานเห็น)").addChannelTypes(ChannelType.GuildText))
    .addChannelOption((o) => o.setName("logs").setDescription("ห้อง Log").addChannelTypes(ChannelType.GuildText))
    .addChannelOption((o) => o.setName("reviews").setDescription("ห้องแสดงรีวิว").addChannelTypes(ChannelType.GuildText)),
  description: "ตั้งค่าห้องออเดอร์/Log/รีวิว",
  minRole: "ADMIN",
  async execute(i) {
    const { guild, settings } = await getSettings();
    const data: Record<string, string> = {};
    const map = { orders: "orderChannelId", logs: "logChannelId", reviews: "reviewChannelId" } as const;
    for (const [opt, key] of Object.entries(map)) { const c = i.options.getChannel(opt); if (c) data[key] = c.id; }
    if (!Object.keys(data).length) return void (await i.reply({ ephemeral: true,
      content: `ปัจจุบัน — ออเดอร์: ${settings.orderChannelId ? `<#${settings.orderChannelId}>` : "-"} | Log: ${settings.logChannelId ? `<#${settings.logChannelId}>` : "-"} | รีวิว: ${settings.reviewChannelId ? `<#${settings.reviewChannelId}>` : "-"}` }));
    await prisma.guildSettings.update({ where: { guildId: guild.id }, data });
    await audit(prisma, guild.id, i.user.id, "settings.channels", "GuildSettings", settings.id, undefined, data);
    await i.reply({ content: "บันทึกการตั้งค่าแล้ว", ephemeral: true });
  },
};

const shop: Command = {
  data: new SlashCommandBuilder().setName("shop").setDescription("เปิด/ปิดรับออเดอร์ (แอดมิน)")
    .addStringOption((o) => o.setName("state").setDescription("สถานะร้าน").setRequired(true)
      .addChoices({ name: "เปิดรับออเดอร์", value: "open" }, { name: "ปิดรับออเดอร์", value: "close" })),
  description: "เปิดหรือปิดรับออเดอร์ชั่วคราว",
  minRole: "ADMIN",
  async execute(i) {
    const { guild, settings } = await getSettings();
    const open = i.options.getString("state", true) === "open";
    await prisma.guildSettings.update({ where: { guildId: guild.id }, data: { shopOpen: open } });
    await audit(prisma, guild.id, i.user.id, "settings.shop", "GuildSettings", settings.id, { shopOpen: settings.shopOpen }, { shopOpen: open });
    await i.reply({ content: open ? "เปิดรับออเดอร์แล้ว" : "ปิดรับออเดอร์แล้ว", ephemeral: true });
  },
};

// ===== bot/interactions/orderFlow.ts =====
const field = (id: string, label: string, style: TextInputStyle, required: boolean, max: number, ph = "") =>
  new ActionRowBuilder<TextInputBuilder>().addComponents(
    new TextInputBuilder().setCustomId(id).setLabel(label).setStyle(style).setRequired(required).setMaxLength(max).setPlaceholder(ph));

const orderPick: SelectHandler = {
  prefix: "order:pick",
  async execute(i) {
    await i.showModal(new ModalBuilder().setCustomId(`order:submit:${i.values[0]}`).setTitle("รายละเอียดงาน").addComponents(
      field("details", "รายละเอียดงาน", TextInputStyle.Paragraph, true, 1000),
      field("budget", "งบประมาณ (บาท)", TextInputStyle.Short, false, 10, "เช่น 500"),
      field("links", "ลิงก์ภาพอ้างอิง (https://…)", TextInputStyle.Paragraph, false, 400),
      field("due", "วันส่งงานที่ต้องการ (YYYY-MM-DD)", TextInputStyle.Short, false, 10, "2026-12-31"),
    ));
  },
};

const formSchema = z.object({
  details: z.string().trim().min(10, "รายละเอียดงานสั้นเกินไป (อย่างน้อย 10 ตัวอักษร)").max(1000),
  links: z.array(z.string().url("ลิงก์ไม่ถูกต้อง").refine((u) => u.startsWith("https://"), "ลิงก์ต้องขึ้นต้นด้วย https://")).max(5),
});

const orderSubmit: ModalHandler = {
  prefix: "order:submit",
  async execute(i, args) {
    await i.deferReply({ ephemeral: true });
    const { settings } = await getSettings();
    if (!settings.shopOpen) return void (await i.editReply({ embeds: [errorEmbed("ขณะนี้ร้านปิดรับออเดอร์ชั่วคราว")] }));
    const raw = (id: string) => i.fields.getTextInputValue(id).trim();
    const parsed = formSchema.safeParse({ details: raw("details"), links: raw("links").split(/\s+/).filter(Boolean) });
    if (!parsed.success) return void (await i.editReply({ embeds: [errorEmbed(parsed.error.issues[0].message)] }));
    let budget: number | null = null;
    if (raw("budget")) {
      budget = bahtToSatang(raw("budget"));
      if (budget === null) return void (await i.editReply({ embeds: [errorEmbed("งบประมาณไม่ถูกต้อง")] }));
    }
    let due: Date | null = null;
    if (raw("due")) {
      due = /^\d{4}-\d{2}-\d{2}$/.test(raw("due")) ? new Date(raw("due") + "T00:00:00+07:00") : null;
      if (!due || isNaN(due.getTime()) || due.getTime() < Date.now())
        return void (await i.editReply({ embeds: [errorEmbed("วันส่งงานไม่ถูกต้องหรืออยู่ในอดีต")] }));
    }
    try {
      const { order, created } = await createOrder({
        customerDiscordId: i.user.id, customerName: i.user.username, packageId: args[0],
        details: parsed.data.details, referenceLinks: parsed.data.links, budgetSatang: budget, dueDate: due, idempotencyKey: i.id,
      });
      await i.editReply({ embeds: [brandEmbed().setTitle(created ? "สร้างออเดอร์สำเร็จ" : "ออเดอร์นี้ถูกสร้างไว้แล้ว").addFields(
        { name: "เลขที่ออเดอร์", value: order.orderNo, inline: true },
        { name: "สถานะ", value: "รอตรวจสอบ", inline: true },
        { name: "ราคา", value: order.priceSatang ? formatBaht(order.priceSatang) : "ทีมงานจะประเมินให้", inline: true },
      ).setDescription("ติดตามได้ด้วย /track หรือ /myorders")] });
    } catch (e) {
      logger.error({ err: e }, "create order failed");
      await i.editReply({ embeds: [errorEmbed(e instanceof AppError ? e.message : "ระบบขัดข้อง กรุณาลองใหม่อีกครั้ง")] });
    }
  },
};

// ===== bot/commands/index.ts =====
const commands = new Map<string, Command>(
  [help, packages, order, myorders, track, review, reviews, setup, shop, dashboard, ping, botinfo].map((c) => [c.data.name, c]),
);

// ===== bot/client.ts =====
const selects: SelectHandler[] = [orderPick];
const modals: ModalHandler[] = [orderSubmit];
const split = (id: string) => { const p = id.split(":"); return { prefix: p.slice(0, 2).join(":"), args: p.slice(2) }; };

async function startBot() {
  // ใช้ Intent เท่าที่จำเป็น (ไม่ต้องเปิด Privileged Intents)
  const client = new Client({ intents: [GatewayIntentBits.Guilds] });
  setClient(client);

  client.once(Events.ClientReady, async (c) => {
    logger.info({ tag: c.user.tag }, "JUKKINGDOM BOT พร้อมใช้งาน");
    try {
      const rest = new REST().setToken(config.DISCORD_TOKEN);
      await rest.put(Routes.applicationGuildCommands(config.DISCORD_CLIENT_ID, config.DISCORD_GUILD_ID),
        { body: [...commands.values()].map((x) => x.data.toJSON()) });
      logger.info({ n: commands.size }, "ลงทะเบียนคำสั่งแล้ว");
    } catch (err) { logger.error({ err }, "ลงทะเบียนคำสั่งไม่สำเร็จ (ตรวจว่าเชิญบอทด้วย scope applications.commands และ GUILD_ID ถูกต้อง)"); }
  });

  client.on(Events.InteractionCreate, async (i: Interaction) => {
    try {
      if (i.isChatInputCommand()) {
        const cmd = commands.get(i.commandName);
        if (!cmd) return;
        if (cmd.minRole && cmd.minRole !== "CUSTOMER") {
          const ok = i.inCachedGuild() && atLeast(await getBotLevel(i.member), cmd.minRole);
          if (!ok) return void (await i.reply({ embeds: [errorEmbed("คุณไม่มีสิทธิ์ใช้คำสั่งนี้")], ephemeral: true }));
        }
        await cmd.execute(i);
      } else if (i.isStringSelectMenu()) {
        const { prefix, args } = split(i.customId);
        await selects.find((h) => h.prefix === prefix)?.execute(i, args);
      } else if (i.isModalSubmit()) {
        const { prefix, args } = split(i.customId);
        await modals.find((h) => h.prefix === prefix)?.execute(i, args);
      }
    } catch (err) {
      logger.error({ err }, "interaction error"); // ไม่ส่ง Stack Trace ให้ผู้ใช้
      if (i.isRepliable()) {
        const embeds = [errorEmbed("เกิดข้อผิดพลาดภายในระบบ กรุณาลองใหม่ภายหลัง")];
        if (i.deferred || i.replied) await i.editReply({ embeds }).catch(() => {});
        else await i.reply({ embeds, ephemeral: true }).catch(() => {});
      }
    }
  });

  await client.login(config.DISCORD_TOKEN);
  return client;
}

// ===== index.ts =====
const server = startWeb();           // เว็บเปิดก่อน เพื่อให้ /health ตอบได้เสมอ
let bot: Awaited<ReturnType<typeof startBot>> | null = null;
startBot().then((c) => { bot = c; }).catch((err) => { logger.error({ err: String(err) }, "บอทเชื่อมต่อ Discord ไม่สำเร็จ ตรวจ DISCORD_TOKEN"); });

const shutdown = async () => { server.close(); await bot?.destroy(); await prisma.$disconnect(); process.exit(0); };
process.on("SIGINT", shutdown); process.on("SIGTERM", shutdown);
process.on("unhandledRejection", (err) => logger.error({ err: String(err) }, "unhandledRejection"));
void config;
EOF_INDEX

RUN npm install --no-audit --no-fund
RUN npm run build
ENV NODE_ENV=production
CMD ["npm", "start"]
