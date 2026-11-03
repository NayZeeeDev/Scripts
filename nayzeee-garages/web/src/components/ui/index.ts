/**
 * nayzeee-garages UI kit — import everything from '@/components/ui'.
 * Contract: docs/UI_KIT.md §2. Styles (ui.css) load with this barrel.
 */
import './ui.css';

export { default as cx } from 'clsx';

export { Icon, ICON_NAMES, VehicleSilhouette, silhouetteFor } from '../icons';
export type { IconName, IconProps, SilhouetteKind } from '../icons';
export { VehicleImage } from '../VehicleImage';
export type { VehicleImageProps } from '../VehicleImage';

export { Window, Panel, Section, OptionRow, Divider } from './Window';
export type { WindowProps, PanelProps, SectionProps, OptionRowProps, DividerProps } from './Window';

export { Modal, ConfirmDialog } from './Modal';
export type { ModalProps, ConfirmDialogProps } from './Modal';

export { Button, IconButton, PillClose, Kbd, KeyHint } from './Button';
export type { ButtonProps, ButtonVariant, ButtonSize, IconButtonProps, PillCloseProps, KbdProps, KeyHintProps } from './Button';

export { Field, Input, NumberInput, SearchInput } from './Field';
export type { FieldProps, InputProps, NumberInputProps, SearchInputProps } from './Field';

export { Select, MultiSelect } from './Select';
export type { SelectOption, SelectProps, MultiSelectProps } from './Select';

export { Toggle, Segmented, Tabs, Slider, ColorSwatches } from './Controls';
export type {
  ToggleProps,
  SegmentedOption,
  SegmentedProps,
  TabItem,
  TabsProps,
  SliderProps,
  ColorSwatchesProps,
} from './Controls';

export {
  Chip,
  Badge,
  PlateTag,
  Stat,
  Bar,
  Ring,
  Pips,
  Meter,
  Avatar,
  BrandMark,
  Spinner,
  Skeleton,
  SkeletonRows,
  EmptyState,
  autoTone,
  initials,
} from './Display';
export type {
  Tone,
  MeterTone,
  ChipProps,
  BadgeProps,
  PlateTagProps,
  StatProps,
  BarProps,
  RingProps,
  PipsProps,
  MeterProps,
  AvatarProps,
  BrandMarkProps,
  SpinnerProps,
  SkeletonProps,
  SkeletonRowsProps,
  EmptyStateProps,
} from './Display';

export { Table, Pagination } from './Table';
export type { TableColumn, TableProps, PaginationProps } from './Table';

export { Tooltip, InfoDot } from './Tooltip';
export type { TooltipProps, InfoDotProps } from './Tooltip';

export { Menu } from './Menu';
export type { MenuItem, MenuProps } from './Menu';
