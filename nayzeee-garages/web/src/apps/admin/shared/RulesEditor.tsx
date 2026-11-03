/**
 * RulesEditor — edit a JobRule[] (job or gang + minimum grade).
 *
 * API
 *   <RulesEditor value onChange options noun? addLabel? emptyText? invalid? disabled? />
 *   - options: JobInfo[] (data.jobs or data.gangs). Rules whose name is unknown stay editable
 *     and are flagged "not found".
 *   - noun: 'job' | 'gang' (wording only).
 * Each row: searchable job Select, minimum-grade Select (from that job's grades), remove.
 * Jobs already used in another row are disabled in the list. "Add job" appends the first
 * unused job.
 */
import { Button, IconButton, Select, cx } from '@/components/ui';
import { t } from '@/lib/i18n';
import type { JobInfo, JobRule } from '@/lib/types';
import { findGroupInfo, gradeOptions } from './labels';

/** Server limit per list (server/locations.lua LIMITS.rules). */
const MAX_RULES = 20;

export interface RulesEditorProps {
  value: JobRule[];
  onChange: (rules: JobRule[]) => void;
  options: JobInfo[];
  noun?: 'job' | 'gang';
  addLabel?: string;
  emptyText?: string;
  invalid?: boolean;
  disabled?: boolean;
  className?: string;
}

export function RulesEditor({
  value,
  onChange,
  options,
  noun = 'job',
  addLabel,
  emptyText,
  invalid = false,
  disabled = false,
  className,
}: RulesEditorProps) {
  const used = new Set(value.map((r) => r.name));
  const unused = options.filter((o) => !used.has(o.name));

  const lowestGrade = (info: JobInfo | undefined) =>
    info && info.grades.length ? Math.min(...info.grades.map((g) => g.grade)) : 0;

  const update = (i: number, rule: JobRule) => onChange(value.map((r, j) => (j === i ? rule : r)));
  const remove = (i: number) => onChange(value.filter((_, j) => j !== i));
  const add = () => {
    const next = unused[0];
    if (!next) return;
    onChange([...value, { name: next.name, minGrade: lowestGrade(next) }]);
  };

  return (
    <div className={cx('nz-admin-rules', invalid && 'is-invalid', className)}>
      {value.length === 0 ? (
        <div className="nz-admin-rules__empty">
          {emptyText ?? (noun === 'gang' ? t('No gangs added yet') : t('No jobs added yet'))}
        </div>
      ) : (
        <div className="nz-admin-rules__list">
          <div className="nz-admin-rules__head">
            <span>{noun === 'gang' ? t('Gang') : t('Job')}</span>
            <span>{t('Minimum grade')}</span>
            <span />
          </div>
          {value.map((rule, i) => {
            const info = findGroupInfo(options, rule.name);
            const jobOptions = [
              ...options.map((o) => ({
                value: o.name,
                label: o.label || o.name,
                hint: o.name !== o.label ? o.name : undefined,
                disabled: o.name !== rule.name && used.has(o.name),
              })),
              ...(info ? [] : [{ value: rule.name, label: rule.name, hint: t('not found'), disabled: false }]),
            ];
            const grades = gradeOptions(info);
            const gradeKnown = grades.some((g) => g.value === rule.minGrade);
            return (
              <div key={`${rule.name}-${i}`} className="nz-admin-rules__row">
                <Select<string>
                  value={rule.name}
                  options={jobOptions}
                  searchable={options.length > 6}
                  icon={noun === 'gang' ? 'users' : 'briefcase'}
                  disabled={disabled}
                  onChange={(name) => update(i, { name, minGrade: lowestGrade(findGroupInfo(options, name)) })}
                />
                <Select<number>
                  value={rule.minGrade}
                  options={gradeKnown ? grades : [...grades, { value: rule.minGrade, label: String(rule.minGrade) }]}
                  disabled={disabled}
                  onChange={(minGrade) => update(i, { ...rule, minGrade })}
                />
                <IconButton
                  icon="trash"
                  size="sm"
                  label={t('Remove')}
                  disabled={disabled}
                  onClick={() => remove(i)}
                  className="nz-admin-rules__remove"
                />
              </div>
            );
          })}
        </div>
      )}
      <div className="nz-admin-rules__foot">
        <Button size="sm" icon="plus" onClick={add} disabled={disabled || unused.length === 0 || value.length >= MAX_RULES}>
          {addLabel ?? (noun === 'gang' ? t('Add gang') : t('Add job'))}
        </Button>
        {options.length === 0 && (
          <span className="nz-admin-rules__note">
            {noun === 'gang' ? t('The framework reported no gangs.') : t('The framework reported no jobs.')}
          </span>
        )}
        {options.length > 0 && unused.length === 0 && value.length > 0 && (
          <span className="nz-admin-rules__note">{noun === 'gang' ? t('Every gang is added.') : t('Every job is added.')}</span>
        )}
      </div>
    </div>
  );
}
