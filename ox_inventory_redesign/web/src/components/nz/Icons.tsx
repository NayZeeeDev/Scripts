import React from 'react';

type IconProps = React.SVGProps<SVGSVGElement> & { size?: string | number };

const make = (paths: React.ReactNode, fill = false) => {
  const Icon: React.FC<IconProps> = ({ size = '1em', ...props }) => (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={fill ? 'currentColor' : 'none'}
      stroke={fill ? 'none' : 'currentColor'}
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      {...props}
    >
      {paths}
    </svg>
  );
  return Icon;
};

export const IconSearch = make(
  <>
    <circle cx="11" cy="11" r="7" />
    <path d="m20 20-3.5-3.5" />
  </>
);
export const IconExpand = make(<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />);
export const IconCompact = make(<path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5" />);
export const IconGear = make(
  <>
    <circle cx="12" cy="12" r="3" />
    <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
  </>
);
export const IconShirt = make(
  <path d="M8 3 3.5 5.5 5 10l2-.8V21h10V9.2l2 .8 1.5-4.5L16 3c-.7 1.4-2.2 2.2-4 2.2S8.7 4.4 8 3z" />
);
export const IconHand = make(
  <path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12m0-1.5v-6a1.5 1.5 0 0 1 3 0V12m0-5.5a1.5 1.5 0 0 1 3 0V12m0-3.5a1.5 1.5 0 0 1 3 0V15a7 7 0 0 1-7 7h-1.5a7 7 0 0 1-5.6-2.8L3.3 15.8a1.6 1.6 0 0 1 2.4-2.1L8 16" />
);
export const IconHandshake = make(
  <>
    <path d="m11 17 2 2a1 1 0 1 0 3-3" />
    <path d="m14 14 2.5 2.5a1 1 0 1 0 3-3l-3.9-3.9a3 3 0 0 0-4.2 0l-.9.9a1 1 0 1 1-3-3l2.8-2.8a5.8 5.8 0 0 1 7 .9L21 7.4" />
    <path d="m21 3 1 11h-2M3 3 2 14l6.5 6.5a1 1 0 1 0 3-3M3 4h8" />
  </>
);
export const IconInfo = make(
  <>
    <path d="M12 11v6" />
    <circle cx="12" cy="7.5" r=".6" fill="currentColor" />
  </>
);
export const IconWallet = make(
  <>
    <path d="M19 7V5a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3v-3" />
    <path d="M3 6v12a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-2" />
  </>
);
export const IconBank = make(<path d="M3 21h18M5 21V10m4 11V10m6 11V10m4 11V10M2 10l10-6 10 6z" />);
export const IconBriefcase = make(
  <>
    <rect x="3" y="7" width="18" height="13" rx="2" />
    <path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 13h18" />
  </>
);
export const IconBag = make(
  <>
    <path d="M6 8h12l-1 12H7z" />
    <path d="M9 8V6a3 3 0 0 1 6 0v2" />
  </>
);
export const IconBackpack = make(
  <path
    d="M9 3h6v2.1A5 5 0 0 1 19 10v9a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-9a5 5 0 0 1 4-4.9zM9 14h6v4H9z"
    fill="currentColor"
    stroke="none"
  />
);
export const IconClose = make(<path d="M18 6 6 18M6 6l12 12" />);
export const IconSwap = make(<path d="M7 4 3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7" />);
export const IconUser = make(
  <>
    <circle cx="12" cy="8" r="4" />
    <path d="M4 21a8 8 0 0 1 16 0" />
  </>
);
export const IconRestore = make(<path d="M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5" />);
export const IconSave = make(
  <>
    <path d="M5 3h11l5 5v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z" />
    <path d="M7 3v5h8M7 21v-7h10v7" />
  </>
);
export const IconPalette = make(
  <>
    <path d="M12 3a9 9 0 0 0 0 18c1 0 1.5-.8 1.5-1.5 0-1-.8-1.3-.8-2.2 0-.8.7-1.3 1.5-1.3H16a5 5 0 0 0 5-5c0-4.4-4-8-9-8z" />
    <circle cx="7.5" cy="11" r="1" fill="currentColor" />
    <circle cx="10" cy="7" r="1" fill="currentColor" />
    <circle cx="15" cy="7.5" r="1" fill="currentColor" />
  </>
);
export const IconSliders = make(<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0M14 4v4M8 10v4M16 16v4" />);
export const IconType = make(<path d="M4 7V5h16v2M9 19h6M12 5v14" />);
export const IconContrast = make(
  <>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor" />
  </>
);
export const IconHexagon = make(<path d="M7 3h10l5 9-5 9H7l-5-9z" />);
export const IconBell = make(<path d="M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.9 1.9 0 0 0 3.4 0" />);
export const IconGrid = make(
  <>
    <rect x="3" y="3" width="7" height="7" rx="1" />
    <rect x="14" y="3" width="7" height="7" rx="1" />
    <rect x="3" y="14" width="7" height="7" rx="1" />
    <rect x="14" y="14" width="7" height="7" rx="1" />
  </>
);
export const IconClock = make(
  <>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 7v5l3 3" />
  </>
);
export const IconChevron = make(<path d="m9 6 6 6-6 6" />);
export const IconMinus = make(<path d="M5 12h14" />);
export const IconPlus = make(<path d="M12 5v14M5 12h14" />);
export const IconBox = make(
  <>
    <path d="M21 8 12 3 3 8v8l9 5 9-5z" />
    <path d="m3 8 9 5 9-5M12 13v8" />
  </>
);
export const IconStore = make(<path d="M3 9 5 4h14l2 5M3 9v11h18V9M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0M9 20v-6h6v6" />);
export const IconHammer = make(<path d="m15 12-8.4 8.4a2 2 0 0 1-2.8-2.8L12.2 9M17.6 15 22 10.6M20 12.6l-6.6-6.6a3 3 0 0 0-4.2 0L8 7.2l2.4.4 6 6 .6 2.4" />);
export const IconCar = make(
  <>
    <path d="M5 17H3v-5l2-5h14l2 5v5h-2M5 12h14" />
    <circle cx="7.5" cy="17" r="2" />
    <circle cx="16.5" cy="17" r="2" />
  </>
);
export const IconDrop = make(<path d="M12 3v12M7 10l5 5 5-5M5 21h14" />);

// Clothing pieces
export const IconHat = make(<path d="M4 16c0-5 3.5-9 8-9s8 4 8 9M2 16h20M8 7.5C8 5 9.8 3 12 3s4 2 4 4.5" />);
export const IconGlasses = make(
  <>
    <circle cx="6.5" cy="14" r="3.5" />
    <circle cx="17.5" cy="14" r="3.5" />
    <path d="M10 14h4M3 14 4.5 7H7M21 14l-1.5-7H17" />
  </>
);
export const IconEar = make(<path d="M6 9a6 6 0 1 1 12 0c0 3-2 4-3 5.5S14 18 14 19a3 3 0 0 1-6 0M9 9a3 3 0 0 1 6 0c0 1.5-1.5 2-2 3" />);
export const IconMask = make(
  <>
    <path d="M4 6c5-2 11-2 16 0v5c0 5-4 9-8 10-4-1-8-5-8-10z" />
    <path d="M8 11h2.5M13.5 11H16" />
  </>
);
export const IconChain = make(<path d="M5 3c0 7 3 11 7 11s7-4 7-11M12 14v3M10 19a2 2 0 1 0 4 0 2 2 0 1 0-4 0" />);
export const IconVest = make(<path d="M8 3 5 6v15h5v-6h4v6h5V6l-3-3-4 4z" />);
export const IconWatch = make(
  <>
    <circle cx="12" cy="12" r="5" />
    <path d="M12 10v2l1 1M9 7.5 9.5 3h5l.5 4.5M9 16.5 9.5 21h5l.5-4.5" />
  </>
);
export const IconBracelet = make(
  <>
    <ellipse cx="12" cy="12" rx="8" ry="5" />
    <ellipse cx="12" cy="12" rx="5" ry="2.5" />
  </>
);
export const IconPants = make(<path d="M6 3h12l1 18h-5l-2-11-2 11H5z" />);
export const IconShoe = make(<path d="M3 17V8h5l2 4 6 1.5c3 .8 5 2 5 3.5v1H3zM3 20h18" />);

// Brand mark (four point star inside a diamond) used when no logo url is configured
export const BrandMark: React.FC<{ size?: string }> = ({ size = '1em' }) => (
  <svg width={size} height={size} viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
    <path
      d="M50 2 63 37 98 50 63 63 50 98 37 63 2 50 37 37Z"
      fill="var(--accent)"
      style={{ filter: 'drop-shadow(0 0 6px rgba(var(--accent-rgb), .45))' }}
    />
    <path d="M50 30 56 44 70 50 56 56 50 70 44 56 30 50 44 44Z" fill="#0d0f0b" />
  </svg>
);
