import React from 'react';
import { useAppSelector } from '../../store';
import { selectConfig } from '../../store/ui';
import { T } from '../../store/strings';
import { formatMoney } from './format';
import { BrandMark, IconBank, IconBriefcase, IconUser, IconWallet } from './Icons';

const Stat: React.FC<{ icon: React.ReactNode; label: string; value: string }> = ({ icon, label, value }) => (
  <div className="nz-stat">
    <div className="nz-stat-icon">{icon}</div>
    <div className="nz-stat-text">
      <span>{label}</span>
      <b title={value}>{value}</b>
    </div>
  </div>
);

const PlayerCard: React.FC = () => {
  const player = useAppSelector((state) => state.ui.player);
  const config = useAppSelector(selectConfig);
  const brand = useAppSelector((state) => (state.ui.draft ?? state.ui.settings).brand);

  if (!config.playerCard) return null;

  const job = player?.job ? (player.grade ? `${player.job} - ${player.grade}` : player.job) : T.unemployed;

  return (
    <div className="nz-player">
      <div className="nz-avatar">
        {player?.avatar ? (
          <img src={player.avatar} alt="" />
        ) : brand ? (
          <BrandMark size="60%" />
        ) : (
          <IconUser size="55%" />
        )}
      </div>
      <div className="nz-player-body">
        <div className="nz-player-name">
          <p>{player?.name || T.player}</p>
          {player?.id !== undefined && <span>#{player.id}</span>}
        </div>
        <div className="nz-player-stats">
          <Stat icon={<IconWallet />} label={T.wallet} value={formatMoney(player?.wallet ?? 0, config.currency)} />
          {config.showBank && player?.bank !== undefined && (
            <Stat icon={<IconBank />} label={T.bank} value={formatMoney(player.bank, config.currency)} />
          )}
          {config.showJob && <Stat icon={<IconBriefcase />} label={T.job} value={job} />}
        </div>
      </div>
    </div>
  );
};

export default PlayerCard;
