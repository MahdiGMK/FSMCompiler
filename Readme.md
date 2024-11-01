<div dir="rtl">

# Usage
<div dir="ltr">

Linux: `./FSMCompiler -h`

Windows: `zig build run -- -h`

e.g. `./FSMCompiler -i test.fsm -o test.c`

<div dir="rtl">

# FSM Syntax

ساختار هر گره در این ماشین به صورت زیر میباشد :
<div dir="ltr">

```
.state_name {
    event_name0 => next_state0;
    event_name1 => next_state1;
    ...
}
```
<div dir="rtl">
علاوه بر این میتوان درون گره های ماشین، گره های دیگری نیز تعریف کرد :
<div dir="ltr">

```
.parent_node {
    _ => .initial_state;
    event_name1 => next_state1;
    ...
    .initial_state {
        event => other_child;
        ...
    }
    .other_child {
        other_event => initial_state;
        ...
    }
}
```
<div dir="rtl">
همانطور که در بالا مشاهده میکنید، رویداد  '_'  عملا حالت اولیه را تعیین میکند. همچنین
برای تعیین کردن حالت های درونی باید در ابتدای نام حالت '.' گذاشته شود و برای
حالات دیگر که درون یک ابرگره میباشند صرفا باید نام آن گره نوشته شود.

علاوه بر این، کل فایل به صورت گره ریشه در نظر گرفته میشود. بنابر این
برای تعیین کردن حالت ابتدایی باید رویداد '_' را تعیین نمود.

در زیر یک نمونه از این نوشتار را مشاهده مینمایید :
<div dir="ltr">

```
_ => .N;
.C {
    _ => .1;
    T<30 => N;
    .1 {
        T>40 => 2;
    }
    .2 {
        T<35 => 1;
        T>50 => 3;
    }
    .3 {
        T<45 => 2;
        T>60 => 4;
    }
    .4 {
        T<55 => 3;
    }
}
.N {
    T<15 => H;
    T>35 => C;
}
.H {
    _ => .1;
    T>20 => N;
    .1 {
        T<10 => 2;
    }
    .2 {
        T>12 => 1;
        T<5 => 3;
    }
    .3 {
        T>7 => 2;
        T<0 => 4;
    }
    .4{
        T>2 => 3;
    }
}
```
<div dir="rtl">
که بعد از کامپایل شدن توسط کامپایلر ما به کد زیر تبدیل میشود :

<div dir="ltr">

```c
#include<string.h>
int main() {
    unsigned long state = 1;
    char evt[256] = "_";
    while(1) {
    unsigned long nstate = state;
        switch(state) {
            case 1: {
                root_reaction();
                nstate = 7;
            } break;
            case 2: {
                root__C_reaction();
                nstate = 3;
                if(strcmp(evt, "T<30") == 0) nstate = 7;
            } break;
            case 3: {
                root__C__1_reaction();
                if(strcmp(evt, "T<30") == 0) nstate = 7;
                if(strcmp(evt, "T>40") == 0) nstate = 4;
            } break;
            case 4: {
                root__C__2_reaction();
                if(strcmp(evt, "T<30") == 0) nstate = 7;
                if(strcmp(evt, "T<35") == 0) nstate = 3;
                if(strcmp(evt, "T>50") == 0) nstate = 5;
            } break;
            case 5: {
                root__C__3_reaction();
                if(strcmp(evt, "T<30") == 0) nstate = 7;
                if(strcmp(evt, "T<45") == 0) nstate = 4;
                if(strcmp(evt, "T>60") == 0) nstate = 6;
            } break;
            case 6: {
                root__C__4_reaction();
                if(strcmp(evt, "T<30") == 0) nstate = 7;
                if(strcmp(evt, "T<55") == 0) nstate = 5;
            } break;
            case 7: {
                root__N_reaction();
                if(strcmp(evt, "T<15") == 0) nstate = 8;
                if(strcmp(evt, "T>35") == 0) nstate = 2;
            } break;
            case 8: {
                root__H_reaction();
                nstate = 9;
                if(strcmp(evt, "T>20") == 0) nstate = 7;
            } break;
            case 9: {
                root__H__1_reaction();
                if(strcmp(evt, "T>20") == 0) nstate = 7;
                if(strcmp(evt, "T<10") == 0) nstate = 10;
            } break;
            case 10: {
                root__H__2_reaction();
                if(strcmp(evt, "T>20") == 0) nstate = 7;
                if(strcmp(evt, "T>12") == 0) nstate = 9;
                if(strcmp(evt, "T<5") == 0) nstate = 11;
            } break;
            case 11: {
                root__H__3_reaction();
                if(strcmp(evt, "T>20") == 0) nstate = 7;
                if(strcmp(evt, "T>7") == 0) nstate = 10;
                if(strcmp(evt, "T<0") == 0) nstate = 12;
            } break;
            case 12: {
                root__H__4_reaction();
                if(strcmp(evt, "T>20") == 0) nstate = 7;
                if(strcmp(evt, "T>2") == 0) nstate = 11;
            } break;
        }
        state = nstate;
    }
}
```
<div dir="rtl">
همانطور که مشاهده مینمایید، این کد عملا معادل نسخه گسترده شده این fsm میباشد.

# Why Zig
شاید این سوال برایتان پیش آمده باشد که چرا از زبان 
zig
برای این برنامه استفاده شده است؟
به طور ساده مشتاق یادگیری این زبان هستم.
دلایل این اشتیاق در زیر آمده است.

1. این زبان، زبانی سیستمی است که قصد دارد جایگزین
c و c++
شود و از طرف دیگر خود کامپایلر این زبان هاست و در واقع سریع ترین کامپایلر 
c و c++
خواهد بود.
2. تمیز بودن کد
3. پشتیبانی بسیار خوب از 
generic و abstraction
بدون آسیب به کارایی برنامه.

برای مطالعه بیشتر میتوانید به 
[zig](https://ziglang.org/)
مراجعه نمایید.

