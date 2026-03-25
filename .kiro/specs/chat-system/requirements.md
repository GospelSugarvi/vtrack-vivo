# Chat System Requirements

## Overview
Built-in chat system to replace Discord and WhatsApp for internal team communication, providing contextual chat rooms with integrated data reporting and real-time messaging capabilities.

## User Stories

### US-1: Store-Based Chat Rooms
**As a** SATOR or SPV  
**I want** to have dedicated chat rooms for each store with integrated daily data  
**So that** I can monitor performance and communicate with promotors in context

**Acceptance Criteria:**
- Each store automatically gets its own chat room
- Chat room shows daily data summary (attendance, stock, sales, achievements)
- Only promotors assigned to that store + their SATOR + SPV can access
- Data updates automatically throughout the day
- Chat messages appear below the data summary

### US-2: Team Chat Rooms
**As a** SATOR  
**I want** to have a team chat room with all my promotors  
**So that** I can broadcast messages and coordinate with my entire team

**Acceptance Criteria:**
- Each SATOR gets a team chat room automatically
- All promotors under that SATOR are automatically added
- SPV has access to all team chat rooms
- Can send broadcasts to entire team
- Team members can discuss and share tips

### US-3: Global Communication
**As a** team member  
**I want** to participate in company-wide discussions  
**So that** I can stay informed about general updates and connect with other teams

**Acceptance Criteria:**
- One global chat room for all users
- All promotors, SATORs, and SPVs have access
- Used for company-wide discussions and cross-team communication

### US-4: Private Messaging
**As a** team member  
**I want** to send private messages to any other team member  
**So that** I can have confidential discussions or personal coaching

**Acceptance Criteria:**
- Any user can start a private chat with any other user
- Only the two participants can see the messages
- Used for sensitive discussions, personal matters, individual coaching

### US-5: Official Announcements
**As a** SPV or Admin  
**I want** to send official announcements to all team members  
**So that** I can communicate important company information effectively

**Acceptance Criteria:**
- Dedicated announcement channel
- Only SPV and Admin can post messages
- All users can read but not reply
- Shows read receipts to track who has seen announcements
- Announcements are retained longer than regular chat messages

### US-6: Real-time Messaging
**As a** user  
**I want** to send and receive messages instantly  
**So that** I can have real-time conversations

**Acceptance Criteria:**
- Messages appear instantly for online users
- Typing indicators show when someone is typing
- Online/offline status is visible
- Messages are queued and sent when user comes back online

### US-7: Message Features
**As a** user  
**I want** to use advanced messaging features  
**So that** I can communicate more effectively

**Acceptance Criteria:**
- Can mention users with @username (with autocomplete)
- Can send photos from camera or gallery
- Can reply to specific messages
- Can react to messages with emojis
- Can edit messages within 1 minute of sending
- Can delete messages within 1 minute of sending
- Can forward messages to other chat rooms

### US-8: Read Receipts and Notifications
**As a** user  
**I want** to know when my messages are read and receive notifications  
**So that** I can track message delivery and stay informed

**Acceptance Criteria:**
- Messages show sent (✓) and read (✓✓) status
- Can see who has read messages in group chats
- Push notifications for new messages
- Special priority notifications for mentions
- Can mute notifications per chat room

### US-9: Automatic Room Management
**As an** admin  
**I want** chat rooms to be created and managed automatically  
**So that** I don't need to manually set up and maintain chat rooms

**Acceptance Criteria:**
- Store chat rooms created automatically when store is added
- Team chat rooms created when SATOR is assigned promotors
- Users automatically added/removed based on their role and assignments
- When promotor changes stores, they're moved to appropriate chat rooms
- When user is deactivated, they're removed from all chat rooms

### US-10: Message History and Cleanup
**As a** user  
**I want** to access recent message history while keeping storage manageable  
**So that** I can reference past conversations without system bloat

**Acceptance Criteria:**
- Regular chat messages are kept for 1 month then auto-deleted
- Announcement messages are kept for 6 months
- Can view message history offline (cached)
- Messages are automatically cleaned up by system

## Technical Requirements

### TR-1: Real-time Communication
- Use Supabase Realtime for instant message delivery
- WebSocket connections for live chat
- Offline message queuing and sync

### TR-2: Push Notifications
- Firebase Cloud Messaging integration
- Different notification sounds for regular messages vs mentions
- Badge counters on app icon

### TR-3: Image Handling
- Cloudinary integration for image uploads
- Auto-compression (max 1920px, 80% JPEG quality)
- Thumbnail previews in chat

### TR-4: Database Schema
- Efficient schema for chat rooms, messages, members, and read receipts
- Proper indexing for performance
- Automatic cleanup jobs for expired messages

### TR-5: Access Control
- Role-based access to different chat room types
- Automatic membership management based on user hierarchy
- Proper security rules to prevent unauthorized access

## Business Rules

### BR-1: Room Access Matrix
| Room Type | Promotor | SATOR | SPV | Admin |
|-----------|----------|-------|-----|-------|
| Own Store | Read/Write | Read/Write | Read/Write | Read/Write |
| Other Store | No Access | No Access | Read/Write | Read/Write |
| Team Chat | Read/Write | Read/Write | Read/Write | Read/Write |
| Global | Read/Write | Read/Write | Read/Write | Read/Write |
| Private | Read/Write | Read/Write | Read/Write | Read/Write |
| Announcements | Read Only | Read Only | Read/Write | Read/Write |

### BR-2: Message Retention
- Regular messages: 1 month retention
- Announcement messages: 6 months retention
- Automatic cleanup via scheduled jobs

### BR-3: User Management
- Users cannot leave chat rooms manually (except private chats)
- Only admins can remove users from rooms
- Membership follows organizational hierarchy automatically

### BR-4: Message Moderation
- No built-in moderation features (trusted internal team)
- No blocking or reporting functionality
- All communication is work-related and professional

## Success Criteria
1. All team members can communicate effectively without external tools
2. SATORs can monitor store performance and communicate in context
3. SPVs can broadcast announcements and coordinate teams
4. Real-time messaging works reliably with <1 second latency
5. Push notifications ensure important messages are not missed
6. System automatically manages chat room membership based on organizational changes
7. Message history is preserved appropriately while managing storage efficiently

## Out of Scope
- File attachments (other than images)
- Voice/video calling
- Message search functionality
- Advanced moderation tools
- Integration with external chat platforms
- Message encryption (internal team communication)