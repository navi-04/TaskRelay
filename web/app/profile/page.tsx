'use client';

import Shell from '@/components/Shell';
import AccountCard from '@/components/profile/AccountCard';
import AiAccess from '@/components/profile/AiAccess';
import AppBlocking from '@/components/profile/AppBlocking';
import Appearance from '@/components/profile/Appearance';
import LabelsEditor from '@/components/profile/LabelsEditor';
import ReminderSettings from '@/components/profile/ReminderSettings';

export default function ProfilePage() {
  return (
    <Shell>
      <h1>Profile</h1>
      <Appearance />
      <AiAccess />
      <ReminderSettings />
      <AppBlocking />
      <LabelsEditor />
      <AccountCard />
    </Shell>
  );
}
