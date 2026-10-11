export const formatWeight = (weight: number) => {
  if (!weight || weight <= 0) return '0.0kg';
  if (weight >= 1000) return `${(weight / 1000).toLocaleString('en-us', { maximumFractionDigits: 2 })}kg`;
  return `${Math.round(weight).toLocaleString('en-us')}g`;
};

export const formatKg = (grams: number) =>
  (Math.round(grams / 100) / 10).toLocaleString('en-us', { maximumFractionDigits: 1 });

export const formatMoney = (value: number | undefined, currency = '$') =>
  value === undefined || value === null ? '-' : `${currency} ${Math.floor(value).toLocaleString('en-us')}`;

export const hexToRgb = (hex: string) => {
  let h = hex.replace('#', '');
  if (h.length === 3)
    h = h
      .split('')
      .map((c) => c + c)
      .join('');
  const n = parseInt(h, 16);
  if (Number.isNaN(n) || h.length !== 6) return '196, 248, 42';
  return `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`;
};
